#!/usr/bin/env python3
"""Rebuild/check ARM parity and validate non-secret deployment parameter contracts."""

import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
BICEP_VERSION = "0.38.33"
PRIVATE_NETWORKS = tuple(ipaddress.ip_network(prefix) for prefix in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))


def resolve_schema(schema, template):
    while "$ref" in schema:
        ref = schema["$ref"]
        if not ref.startswith("#/"):
            raise ValueError("Only local ARM type references are supported")
        overrides = {key: value for key, value in schema.items() if key != "$ref"}
        schema = template
        for part in ref[2:].split("/"):
            schema = schema[part.replace("~1", "/").replace("~0", "~")]
        schema = {**schema, **overrides}
    return schema


def validate_value(value, schema, template, path):
    schema = resolve_schema(schema, template)
    if value is None and schema.get("nullable"):
        return
    kind = schema["type"].lower()
    valid_type = {
        "object": isinstance(value, dict),
        "secureobject": isinstance(value, dict),
        "string": isinstance(value, str),
        "securestring": isinstance(value, str),
        "array": isinstance(value, list),
        "bool": isinstance(value, bool),
        "int": isinstance(value, int) and not isinstance(value, bool),
    }.get(kind, False)
    if not valid_type:
        raise ValueError(f"{path}: expected {kind}")
    if "allowedValues" in schema and value not in schema["allowedValues"]:
        raise ValueError(f"{path}: value is not allowed")
    for bound, comparator in (("minLength", lambda a, b: a >= b), ("maxLength", lambda a, b: a <= b)):
        if bound in schema and not comparator(len(value), schema[bound]):
            raise ValueError(f"{path}: violates {bound}")
    if kind in ("object", "secureobject"):
        properties = schema.get("properties", {})
        for name, child in properties.items():
            if name not in value and not resolve_schema(child, template).get("nullable", False):
                raise ValueError(f"{path}.{name}: missing property")
        for name, child in value.items():
            if name in properties:
                validate_value(child, properties[name], template, f"{path}.{name}")
            elif schema.get("additionalProperties") is False:
                raise ValueError(f"{path}.{name}: unknown property")
    if kind == "array" and "items" in schema:
        for index, child in enumerate(value):
            validate_value(child, schema["items"], template, f"{path}[{index}]")


def require_uuid(value, label):
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError) as error:
        raise ValueError(f"{label}: expected a UUID") from error
    if parsed.int == 0:
        raise ValueError(f"{label}: zero UUID is a placeholder")


def validate_parameters(parameters, template, allow_placeholders=False):
    values = parameters["parameters"]
    schemas = template["parameters"]
    for name, schema in schemas.items():
        if name not in values and "defaultValue" not in schema and not resolve_schema(schema, template).get("nullable"):
            raise ValueError(f"{name}: missing parameter")
    for name, supplied in values.items():
        if name not in schemas:
            raise ValueError(f"{name}: unknown parameter")
        schema = resolve_schema(schemas[name], template)
        if set(supplied) == {"reference"}:
            if schema["type"].lower() != "securestring":
                raise ValueError(f"{name}: Key Vault reference requires secureString")
            reference = supplied["reference"]
            if not reference.get("keyVault", {}).get("id") or not reference.get("secretName"):
                raise ValueError(f"{name}: incomplete Key Vault reference")
        elif set(supplied) == {"value"}:
            if schema["type"].lower().startswith("secure"):
                raise ValueError(f"{name}: use a Key Vault reference, not a plaintext parameter file")
            validate_value(supplied["value"], schema, template, name)
        else:
            raise ValueError(f"{name}: supply exactly one value or Key Vault reference")
    if allow_placeholders:
        return
    serialized = json.dumps(parameters)
    if re.search(r"REPLACE|00000000-0000-0000-0000-000000000000|@[^\" ]+\.example", serialized, re.I):
        raise ValueError("Replace example resource IDs, workspace IDs, and administrator identities before deployment")
    if "environment" in values:
        environment = values["environment"]["value"]
        if not re.fullmatch(r"[a-z][a-z0-9]{2,11}", environment["namePrefix"]):
            raise ValueError("environment.namePrefix: use 3-12 lowercase letters/digits, starting with a letter")
        network = ipaddress.ip_network(environment["vnetAddressPrefix"])
        if network.version != 4 or network.prefixlen != 16 or not any(network.subnet_of(block) for block in PRIVATE_NETWORKS):
            raise ValueError("environment.vnetAddressPrefix: expected a private IPv4 /16")
        for fqdn in environment["httpsAllowedFqdns"]:
            if not re.fullmatch(r"(?:\*\.)?(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}", fqdn):
                raise ValueError("environment.httpsAllowedFqdns: expected DNS names, not URLs or unrestricted wildcards")
        if "fabric" in values:
            principal = values["fabric"]["value"]["landingDataPrincipalId"]
            if principal:
                require_uuid(principal, "fabric.landingDataPrincipalId")
    if "providerPrivateLinkServiceId" in values:
        resource_id = values["providerPrivateLinkServiceId"]["value"]
        if not re.fullmatch(
            r"/subscriptions/([0-9a-fA-F-]{36})/resourceGroups/[^/]+/providers/"
            r"Microsoft\.Fabric/privateLinkServicesForFabric/[^/]+",
            resource_id,
            re.I,
        ):
            raise ValueError("providerPrivateLinkServiceId: expected a Fabric workspace Private Link ARM resource ID")
        require_uuid(resource_id.split("/")[2], "provider subscription")
    if "workspaceId" in values:
        require_uuid(values["workspaceId"]["value"], "workspaceId")
    if "sqlServerFqdn" in values:
        fqdn = values["sqlServerFqdn"]["value"]
        if not re.fullmatch(r"[a-zA-Z0-9.-]+\.datawarehouse\.fabric\.microsoft\.com", fqdn):
            raise ValueError("sqlServerFqdn: expected the exact provider-returned commercial-cloud SQL hostname")
        address = ipaddress.ip_address(values["sqlPrivateIp"]["value"])
        if address.version != 4 or not any(address in block for block in PRIVATE_NETWORKS):
            raise ValueError("sqlPrivateIp: expected a verified private IPv4 address")


def compile_templates(write=False):
    compiler = os.environ.get("BICEP") or shutil.which("bicep")
    if not compiler:
        raise ValueError(f"Bicep {BICEP_VERSION} is required; install it or set BICEP to its executable")
    version = subprocess.run([compiler, "--version"], check=True, capture_output=True, text=True).stdout
    if not version.startswith(f"Bicep CLI version {BICEP_VERSION} "):
        raise ValueError(f"Use Bicep {BICEP_VERSION} for reproducible checked-in ARM templates")
    count = 0
    for source in sorted(ROOT.rglob("*.bicep")):
        if source.name == "types.bicep":
            continue
        compiled = subprocess.run([compiler, "build", str(source), "--stdout"], capture_output=True, text=True)
        if compiled.returncode or compiled.stderr.strip():
            raise ValueError(f"Bicep compilation/lint failed for {source.relative_to(ROOT)}:\n{compiled.stderr}")
        target = source.with_suffix(".json")
        if write:
            target.write_text(compiled.stdout)
        elif not target.exists() or json.loads(target.read_text()) != json.loads(compiled.stdout):
            raise ValueError(f"{target.relative_to(ROOT)} is stale; regenerate with --write")
        count += 1
    print(f"Compiled and {'generated' if write else 'verified ARM parity for'} {count} Bicep templates; no diagnostics.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Regenerate committed ARM JSON from Bicep")
    parser.add_argument("--parameters", type=Path, help="Validate a real deployment parameter file; placeholders rejected")
    parser.add_argument("--template", type=Path, help="ARM template corresponding to --parameters")
    args = parser.parse_args()
    if bool(args.parameters) != bool(args.template):
        parser.error("--parameters and --template must be supplied together")
    compile_templates(args.write)
    for example in sorted(ROOT.rglob("parameters.example.json")):
        validate_parameters(json.loads(example.read_text()), json.loads(example.with_name("main.json").read_text()), True)
    print("All six example parameter files match their compiled ARM contracts.")
    if args.parameters:
        validate_parameters(json.loads(args.parameters.read_text()), json.loads(args.template.read_text()))
        print("Deployment parameter contract passed; cloud permissions, approvals, DNS, and runtime access remain separate checks.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        sys.exit(1)
