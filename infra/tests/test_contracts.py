import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from validate import validate_parameters  # noqa: E402


def read(relative):
    return json.loads((ROOT / relative).read_text())


def resources(template):
    entries = template["resources"]
    return list(entries.values()) if isinstance(entries, dict) else entries


def resource(template, kind):
    found = [entry for entry in resources(template) if entry["type"] == kind]
    if len(found) != 1:
        raise AssertionError(f"Expected one {kind}, found {len(found)}")
    return found[0]


def nested(template, name):
    entries = template["resources"]
    if isinstance(entries, dict):
        return entries[name]
    return next(entry for entry in entries if entry["name"] == name)


class ArchitectureContracts(unittest.TestCase):
    def test_four_distinct_consumer_transport_combinations(self):
        variants = [
            ("01-azure-public-sql", True, False),
            ("02-azure-private-sql", False, False),
            ("03-customer-fabric-public-sql", True, True),
            ("04-customer-fabric-private-sql", False, True),
        ]
        for folder, public, fabric in variants:
            with self.subTest(folder=folder):
                template = read(f"{folder}/main.json")
                call = resource(template, "Microsoft.Resources/deployments")
                parameters = call["properties"]["parameters"]
                expected = True if public else "[not(parameters('privateConnectivityApproved'))]"
                self.assertEqual(parameters["publicSql"]["value"], expected)
                self.assertEqual(parameters["customerFabric"]["value"], fabric)
                self.assertEqual(template["parameters"]["adminPassword"]["type"].lower(), "securestring")
                self.assertNotIn("defaultValue", template["parameters"]["adminPassword"])
                if not public:
                    self.assertEqual(template["parameters"]["privateConnectivityApproved"]["allowedValues"], [True])
                    self.assertNotIn("defaultValue", template["parameters"]["privateConnectivityApproved"])
                shared = call["properties"]["template"]
                self.assertEqual(nested(shared, "epicEndpoint")["condition"], "[not(parameters('publicSql'))]")
                for name in ("capacity", "storage"):
                    self.assertEqual(nested(shared, name)["condition"], "[parameters('customerFabric')]")
                self.assertEqual(shared["parameters"]["adminPassword"]["type"].lower(), "securestring")
                self.assertIn(".outputs.connections.value", template["outputs"]["connections"]["value"])

    def test_public_sql_rules_are_empty_in_private_mode(self):
        template = read("shared/modules/network.json")
        count = template["variables"]["copy"][0]["count"]
        self.assertEqual(count, "[length(if(parameters('publicSql'), parameters('sqlServiceTags'), createArray()))]")
        self.assertTrue(template["variables"]["sqlFirewallRules"].startswith("[if(parameters('publicSql'),"))
        self.assertTrue(template["variables"]["sqlFirewallRules"].endswith(", createArray())]"))
        nsg = resource(template, "Microsoft.Network/networkSecurityGroups")
        self.assertIn("variables('publicSqlRules')", nsg["properties"]["securityRules"])
        rules = resource(template, "Microsoft.Network/firewallPolicies/ruleCollectionGroups")
        network_rules = rules["properties"]["ruleCollections"][0]["rules"]
        self.assertIn("variables('sqlFirewallRules')", network_rules)
        self.assertNotIn("'Https', 'port', 1433", json.dumps(template))

    def test_vm_has_no_public_address_and_trusted_launch(self):
        template = read("shared/modules/client.json")
        nic = resource(template, "Microsoft.Network/networkInterfaces")
        self.assertNotIn("publicIPAddress", json.dumps(nic))
        self.assertEqual(nic["properties"]["dnsSettings"]["dnsServers"], ["[parameters('dnsServerIp')]"])
        vm = resource(template, "Microsoft.Compute/virtualMachines")
        security = vm["properties"]["securityProfile"]
        self.assertEqual(security["securityType"], "TrustedLaunch")
        self.assertEqual(security["uefiSettings"], {"secureBootEnabled": True, "vTpmEnabled": True})
        self.assertEqual(vm["properties"]["osProfile"]["adminPassword"], "[parameters('adminPassword')]")
        self.assertNotIn("adminPassword", json.dumps(template["outputs"]))

    def test_private_endpoint_uses_manual_approval_and_workspace_group(self):
        template = read("shared/modules/workspace-private-endpoint.json")
        endpoint = resource(template, "Microsoft.Network/privateEndpoints")
        self.assertNotIn("privateLinkServiceConnections", endpoint["properties"])
        connections = endpoint["properties"]["manualPrivateLinkServiceConnections"]
        self.assertEqual(connections[0]["properties"]["groupIds"], ["workspace"])
        self.assertEqual(connections[0]["properties"]["privateLinkServiceId"], "[parameters('providerPrivateLinkServiceId')]")
        dns = resource(template, "Microsoft.Network/privateDnsZones")
        self.assertEqual(dns["name"], "privatelink.fabric.microsoft.com")

    def test_provider_resource_matches_documented_workspace_contract(self):
        template = read("shared/provider/main.json")
        service = resource(template, "Microsoft.Fabric/privateLinkServicesForFabric")
        self.assertEqual(service["apiVersion"], "2024-06-01")
        self.assertEqual(service["location"], "global")
        self.assertEqual(service["properties"]["tenantId"], "[tenant().tenantId]")
        self.assertEqual(service["properties"]["workspaceId"], "[parameters('workspaceId')]")

    def test_sql_dns_uses_verified_host_and_ip_not_generated_names(self):
        template = read("shared/consumer-sql-dns/main.json")
        zone = resource(template, "Microsoft.Network/privateDnsZones")
        self.assertEqual(zone["name"], "[parameters('sqlServerFqdn')]")
        record = resource(template, "Microsoft.Network/privateDnsZones/A")
        self.assertEqual(record["properties"]["aRecords"][0]["ipv4Address"], "[parameters('sqlPrivateIp')]")
        self.assertNotIn("wildcard", json.dumps(template).lower())

    def test_landing_storage_is_private_keyless_and_container_scoped(self):
        template = read("shared/modules/landing-storage.json")
        account = resource(template, "Microsoft.Storage/storageAccounts")
        settings = account["properties"]
        self.assertEqual(settings["publicNetworkAccess"], "Disabled")
        self.assertFalse(settings["allowSharedKeyAccess"])
        self.assertFalse(settings["allowBlobPublicAccess"])
        self.assertTrue(settings["isHnsEnabled"])
        self.assertTrue(settings["encryption"]["requireInfrastructureEncryption"])
        writer = resource(template, "Microsoft.Authorization/roleAssignments")
        self.assertEqual(writer["condition"], "[not(empty(parameters('dataPrincipalId')))]")
        self.assertIn("/blobServices/{1}/containers/{2}", writer["scope"])
        self.assertTrue(writer["scope"].endswith(", 'default', 'landing')]"))
        self.assertIn("ba92f5b4-2d11-453d-a403-e96b0029c9fe", writer["properties"]["roleDefinitionId"])
        services = template["variables"]["services"]
        self.assertEqual({entry["group"] for entry in services}, {"blob", "dfs"})

    def test_customer_stack_does_not_deploy_provider_or_identity_objects(self):
        shared = read("shared/customer-environment.json")
        all_types = set()

        def visit(template):
            for entry in resources(template):
                all_types.add(entry["type"])
                if entry["type"] == "Microsoft.Resources/deployments":
                    visit(entry["properties"]["template"])

        visit(shared)
        self.assertNotIn("Microsoft.Fabric/privateLinkServicesForFabric", all_types)
        self.assertNotIn("Microsoft.Sql/servers", all_types)
        self.assertFalse(any("servicePrincipals" in kind for kind in all_types))


class ParameterContracts(unittest.TestCase):
    def setUp(self):
        self.template = read("04-customer-fabric-private-sql/main.json")
        self.example = read("04-customer-fabric-private-sql/parameters.example.json")

    def test_all_examples_match_their_template_types(self):
        examples = list(ROOT.rglob("parameters.example.json"))
        self.assertEqual(len(examples), 6)
        for path in examples:
            with self.subTest(path=path):
                validate_parameters(json.loads(path.read_text()), json.loads(path.with_name("main.json").read_text()), True)

    def test_examples_cannot_be_mistaken_for_deployment_ready_inputs(self):
        with self.assertRaisesRegex(ValueError, "Replace example"):
            validate_parameters(self.example, self.template)

    def test_private_signoff_cannot_be_false_or_omitted(self):
        for value in (False, None):
            parameters = copy.deepcopy(self.example)
            if value is None:
                del parameters["parameters"]["privateConnectivityApproved"]
            else:
                parameters["parameters"]["privateConnectivityApproved"]["value"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_parameters(parameters, self.template, True)

    def test_plaintext_vm_passwords_are_rejected(self):
        self.example["parameters"]["adminPassword"] = {"value": "not-a-real-secret"}
        with self.assertRaisesRegex(ValueError, "Key Vault reference"):
            validate_parameters(self.example, self.template, True)

    def test_empty_fabric_admins_are_rejected(self):
        self.example["parameters"]["fabric"]["value"]["administrators"] = []
        with self.assertRaisesRegex(ValueError, "minLength"):
            validate_parameters(self.example, self.template, True)

    def test_unknown_environment_properties_are_rejected(self):
        self.example["parameters"]["environment"]["value"]["typo"] = True
        with self.assertRaisesRegex(ValueError, "unknown property"):
            validate_parameters(self.example, self.template, True)

    def real_shaped_parameters(self):
        parameters = copy.deepcopy(self.example)
        values = parameters["parameters"]
        values["adminPassword"]["reference"]["keyVault"]["id"] = (
            "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/secrets/"
            "providers/Microsoft.KeyVault/vaults/cogito-test-vault"
        )
        values["providerPrivateLinkServiceId"]["value"] = (
            "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/provider/"
            "providers/Microsoft.Fabric/privateLinkServicesForFabric/cogito-test-link"
        )
        values["fabric"]["value"]["administrators"] = ["fabric-admin@example.org"]
        return parameters

    def test_valid_shaped_deployment_parameters_pass_without_cloud_calls(self):
        validate_parameters(self.real_shaped_parameters(), self.template)

    def test_network_prefix_must_be_rfc1918_ipv4_slash16(self):
        for prefix in ("10.60.0.0/24", "203.0.0.0/16", "198.18.0.0/16", "2001:db8::/16"):
            parameters = self.real_shaped_parameters()
            parameters["parameters"]["environment"]["value"]["vnetAddressPrefix"] = prefix
            with self.subTest(prefix=prefix), self.assertRaises(ValueError):
                validate_parameters(parameters, self.template)

    def test_provider_workspace_guid_cannot_replace_private_link_resource_id(self):
        parameters = self.real_shaped_parameters()
        parameters["parameters"]["providerPrivateLinkServiceId"]["value"] = "22222222-2222-2222-2222-222222222222"
        with self.assertRaisesRegex(ValueError, "Fabric workspace Private Link ARM resource ID"):
            validate_parameters(parameters, self.template)

    def test_wide_web_wildcards_are_rejected(self):
        parameters = self.real_shaped_parameters()
        parameters["parameters"]["environment"]["value"]["httpsAllowedFqdns"] = ["*"]
        with self.assertRaisesRegex(ValueError, "unrestricted wildcards"):
            validate_parameters(parameters, self.template)


if __name__ == "__main__":
    unittest.main()
