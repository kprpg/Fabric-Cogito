const pptxgen = require("pptxgenjs");
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
const sharp = require("sharp");
const fa = require("react-icons/fa");

const FONT = "Segoe UI";
const C = {
  navy: "0B2A6F", blue: "1F5FBF", blueBg: "EEF4FC", teal: "0E7C7B", tealBg: "E8F5F4",
  slate: "3F4A5A", slateBg: "F2F4F7", green: "2E8B57", greenBg: "EAF6EF", purple: "6B3FA0",
  purpleBg: "F1EBF8", gold: "9A7B12", goldBg: "FBF5E1", amber: "D9822B", ink: "1E2A3A",
  muted: "5B6B80", white: "FFFFFF", line: "C9D3E0",
};

async function icon(name, color, size = 256) {
  const svg = renderToStaticMarkup(React.createElement(fa[name], { color: "#" + color, size: String(size) }));
  const buf = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + buf.toString("base64");
}

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
pres.title = "Private Network Connectivity: Fabric / Power BI to On-Premises SQL";
pres.author = "Fabric-Cogito";

const cache = {};
async function ic(name, color) {
  const k = name + color;
  if (!cache[k]) cache[k] = await icon(name, color);
  return cache[k];
}

function footer(slide, n, text) {
  slide.addShape(pres.shapes.RECTANGLE, { x: 0, y: 7.05, w: 13.33, h: 0.45, fill: { color: C.navy }, line: { color: C.navy } });
  slide.addText(text, { x: 0.3, y: 7.05, w: 11, h: 0.45, fontFace: FONT, fontSize: 12, italic: true, bold: true, color: C.white, valign: "middle", margin: 0 });
  slide.addText(String(n), { x: 12.2, y: 7.05, w: 0.85, h: 0.45, fontFace: FONT, fontSize: 11, color: C.white, align: "right", valign: "middle", margin: 0 });
}

async function zone(slide, z) {
  const { x, y, w, h, color, bg, title, sub } = z;
  slide.addShape(pres.shapes.RECTANGLE, { x, y, w, h, fill: { color: bg }, line: { color, width: 1.75 } });
  slide.addShape(pres.shapes.RECTANGLE, { x, y, w, h: 0.55, fill: { color }, line: { color } });
  slide.addText([
    { text: title, options: { bold: true, fontSize: 13, breakLine: true } },
    { text: sub, options: { fontSize: 9.5 } },
  ], { x: x + 0.1, y, w: w - 0.2, h: 0.55, fontFace: FONT, color: C.white, align: "center", valign: "middle", margin: 0 });
  const nodeH = 0.74, gap = 0.16, nx = x + 0.15, nw = w - 0.3;
  let ny = y + 0.55 + 0.1;
  for (let i = 0; i < z.nodes.length; i++) {
    const n = z.nodes[i];
    slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: nx, y: ny, w: nw, h: nodeH, rectRadius: 0.06, fill: { color: C.white }, line: { color: n.accent || color, width: 1.25 } });
    slide.addShape(pres.shapes.OVAL, { x: nx + 0.1, y: ny + (nodeH - 0.44) / 2, w: 0.44, h: 0.44, fill: { color: n.accent || color }, line: { color: n.accent || color } });
    slide.addImage({ data: await ic(n.icon, "FFFFFF"), x: nx + 0.1 + 0.11, y: ny + (nodeH - 0.44) / 2 + 0.11, w: 0.22, h: 0.22 });
    slide.addText([
      { text: n.label, options: { bold: true, fontSize: 10.5, color: C.ink, breakLine: true } },
      { text: n.sub, options: { fontSize: 9, color: C.muted } },
    ], { x: nx + 0.65, y: ny, w: nw - 0.72, h: nodeH, fontFace: FONT, valign: "middle", margin: 0 });
    if (i < z.nodes.length - 1) {
      slide.addShape(pres.shapes.LINE, { x: nx + nw / 2, y: ny + nodeH, w: 0, h: gap, line: { color: color, width: 1.5, dashType: "solid" } });
    }
    ny += nodeH + gap;
  }
}

function link(slide, x, w, cy, l) {
  slide.addShape(pres.shapes.LINE, {
    x, y: cy, w, h: 0,
    line: { color: l.color, width: 2.25, dashType: l.dash || "solid", beginArrowType: l.both ? "triangle" : undefined, endArrowType: "triangle" },
  });
  slide.addShape(pres.shapes.CLOUD, { x: x + 0.12, y: cy - 0.5, w: w - 0.24, h: 1.0, fill: { color: C.white }, line: { color: l.color, width: 1.5 } });
  slide.addText(l.title, { x: x + 0.12, y: cy - 0.5, w: w - 0.24, h: 1.0, fontFace: FONT, fontSize: 9, bold: true, color: C.navy, align: "center", valign: "middle", margin: 0 });
  slide.addText(l.caption, { x: x + 0.1, y: cy + 0.58, w: w - 0.2, h: 0.75, fontFace: FONT, fontSize: 9, italic: true, color: l.color === C.amber ? "9A5A12" : C.muted, align: "center", valign: "top", margin: 0 });
}

function card(slide, c, x, y, w, h) {
  slide.addShape(pres.shapes.RECTANGLE, { x, y, w, h, fill: { color: C.white }, line: { color: c.color, width: 1.25 } });
  slide.addShape(pres.shapes.RECTANGLE, { x, y, w, h: 0.58, fill: { color: c.color }, line: { color: c.color } });
  slide.addShape(pres.shapes.OVAL, { x: x + 0.1, y: y + 0.1, w: 0.38, h: 0.38, fill: { color: C.white }, line: { color: C.white } });
  slide.addText(String(c.n), { x: x + 0.1, y: y + 0.1, w: 0.38, h: 0.38, fontFace: FONT, fontSize: 13, bold: true, color: c.color, align: "center", valign: "middle", margin: 0 });
  slide.addText([
    { text: c.title, options: { bold: true, fontSize: 11.5, breakLine: true } },
    { text: c.q, options: { italic: true, fontSize: 9 } },
  ], { x: x + 0.56, y, w: w - 0.62, h: 0.58, fontFace: FONT, color: C.white, valign: "middle", margin: 0 });
  slide.addText(c.bullets.map((b, i) => ({ text: b, options: { bullet: { indent: 11 }, breakLine: i < c.bullets.length - 1, paraSpaceAfter: 2 } })),
    { x: x + 0.08, y: y + 0.62, w: w - 0.16, h: h - 0.62 - 0.46, fontFace: FONT, fontSize: 9.5, color: C.ink, valign: "top", margin: [2, 2, 0, 2] });
  slide.addShape(pres.shapes.RECTANGLE, { x: x + 0.08, y: y + h - 0.44, w: w - 0.16, h: 0.38, fill: { color: c.bg }, line: { color: c.bg } });
  slide.addText([
    { text: "Outcome: ", options: { bold: true, color: c.color } },
    { text: c.outcome, options: { color: C.ink } },
  ], { x: x + 0.12, y: y + h - 0.44, w: w - 0.24, h: 0.38, fontFace: FONT, fontSize: 9, valign: "middle", margin: 0 });
}

async function diagramSlide(p) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.3, y: 0.28, w: 1.35, h: 0.4, rectRadius: 0.08, fill: { color: C.navy }, line: { color: C.navy } });
  s.addText("PATTERN " + p.n, { x: 0.3, y: 0.28, w: 1.35, h: 0.4, fontFace: FONT, fontSize: 12, bold: true, color: C.white, align: "center", valign: "middle", margin: 0, charSpacing: 2 });
  s.addText(p.title, { x: 1.8, y: 0.15, w: 9.7, h: 0.6, fontFace: FONT, fontSize: 25, bold: true, color: C.navy, align: "center", valign: "middle", margin: 0 });
  s.addText(p.subtitle, { x: 1.2, y: 0.74, w: 10.9, h: 0.32, fontFace: FONT, fontSize: 13, bold: true, color: C.slate, align: "center", valign: "middle", margin: 0 });
  s.addText(p.tagline, { x: 1.2, y: 1.04, w: 10.9, h: 0.3, fontFace: FONT, fontSize: 12, color: C.blue, align: "center", valign: "middle", margin: 0 });
  s.addImage({ data: await ic(p.badgeIcon, C.blue), x: 11.95, y: 0.3, w: 0.36, h: 0.36 });
  s.addText(p.badge, { x: 10.95, y: 0.66, w: 2.1, h: 0.3, fontFace: FONT, fontSize: 9, color: C.muted, align: "right", margin: 0 });

  const zy = 1.45, zh = 3.15, cy = 3.3;
  await zone(s, { x: 0.3, y: zy, w: 3.2, h: zh, color: C.slate, bg: C.slateBg, ...p.left });
  link(s, 3.5, 1.35, cy, p.link1);
  await zone(s, { x: 4.85, y: zy, w: 3.9, h: zh, color: C.blue, bg: C.blueBg, ...p.mid });
  link(s, 8.75, 1.35, cy, p.link2);
  await zone(s, { x: 10.1, y: zy, w: 2.95, h: zh, color: C.teal, bg: C.tealBg, ...p.right });

  const cw = (13.33 - 0.6 - 3 * 0.15) / 4, cyy = 4.75, ch = 2.2;
  p.cards.forEach((c, i) => card(s, c, 0.3 + i * (cw + 0.15), cyy, cw, ch));
  footer(s, p.slideNo, p.footer);
  s.addNotes(p.notes);
  return s;
}

const ON_PREM = { title: "Customer On-Premises", sub: "Datacenter / corporate network" };
const FABRIC = (nodes) => ({ title: "Microsoft Fabric / Power BI", sub: "Microsoft-managed SaaS (your tenant)", nodes });
const CARD_COLORS = [
  { color: C.blue, bg: C.blueBg }, { color: C.green, bg: C.greenBg },
  { color: C.purple, bg: C.purpleBg }, { color: C.gold, bg: C.goldBg },
];
const mkCards = (arr) => arr.map((c, i) => ({ n: i + 1, ...CARD_COLORS[i], ...c }));

async function main() {
  // ---------- Slide 1: Title ----------
  {
    const s = pres.addSlide();
    s.background = { color: C.navy };
    s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 0.35, h: 7.5, fill: { color: C.teal }, line: { color: C.teal } });
    s.addText("Private Network Connectivity", { x: 0.9, y: 1.7, w: 11.5, h: 0.9, fontFace: FONT, fontSize: 44, bold: true, color: C.white, margin: 0 });
    s.addText("Microsoft Fabric & Power BI to On-Premises SQL Server", { x: 0.9, y: 2.6, w: 11.5, h: 0.6, fontFace: FONT, fontSize: 26, color: "CADCFC", margin: 0 });
    s.addText("Four reference combinations using ExpressRoute, Site-to-Site VPN, VNet data gateway, on-premises data gateway and managed private endpoints", { x: 0.9, y: 3.4, w: 9.6, h: 0.8, fontFace: FONT, fontSize: 16, color: "CADCFC", margin: 0 });
    const chips = [["1", "VNet data gateway + ExpressRoute"], ["2", "VNet data gateway + S2S VPN"], ["3", "On-premises data gateway"], ["4", "Managed private endpoint + PLS"]];
    for (let i = 0; i < 4; i++) {
      const x = 0.9 + i * 2.95;
      s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 4.7, w: 2.75, h: 0.95, rectRadius: 0.08, fill: { color: "16397F" }, line: { color: "3D63B8", width: 1 } });
      s.addShape(pres.shapes.OVAL, { x: x + 0.15, y: 4.95, w: 0.45, h: 0.45, fill: { color: C.teal }, line: { color: C.teal } });
      s.addText(chips[i][0], { x: x + 0.15, y: 4.95, w: 0.45, h: 0.45, fontFace: FONT, fontSize: 15, bold: true, color: C.white, align: "center", valign: "middle", margin: 0 });
      s.addText(chips[i][1], { x: x + 0.72, y: 4.7, w: 1.95, h: 0.95, fontFace: FONT, fontSize: 12, bold: true, color: C.white, valign: "middle", margin: 0 });
    }
    s.addText("Architecture options for discussion", { x: 0.9, y: 6.6, w: 8, h: 0.4, fontFace: FONT, fontSize: 12, italic: true, color: "9DB4E8", margin: 0 });
    s.addNotes("Research summary deck. Sources: Microsoft Learn - What is a virtual network data gateway; Create virtual network data gateways; Use virtual network data gateway and data sources in Power BI; Connect to on-premises data sources using Fabric managed private endpoints; On-premises data gateway architecture.");
  }

  // ---------- Slide 2: Building blocks ----------
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    s.addText("Three connectors, two hybrid links, four combinations", { x: 0.3, y: 0.2, w: 12.7, h: 0.6, fontFace: FONT, fontSize: 27, bold: true, color: C.navy, align: "center", margin: 0 });
    s.addText("First clarify the building blocks: where the connector runs and which Fabric / Power BI workloads it serves", { x: 0.3, y: 0.78, w: 12.7, h: 0.35, fontFace: FONT, fontSize: 13, bold: true, color: C.slate, align: "center", margin: 0 });
    s.addText("Private path • Gateway placement • Workload coverage", { x: 0.3, y: 1.1, w: 12.7, h: 0.3, fontFace: FONT, fontSize: 12, color: C.blue, align: "center", margin: 0 });

    const tiles = [
      { color: C.blue, bg: C.blueBg, icon: "FaProjectDiagram", title: "VNet data gateway", where: "Runs in YOUR Azure VNet (Microsoft-managed containers in a delegated subnet). It exists only in Azure; there is no on-premises variant.",
        wl: "Semantic models, paginated reports, Dataflow Gen2, pipelines, Copy job, Mirroring", link: "Reaches on-prem SQL through ExpressRoute or Site-to-Site VPN attached to the VNet" },
      { color: C.slate, bg: C.slateBg, icon: "FaServer", title: "On-premises data gateway", where: "Installed on Windows servers in YOUR datacenter. This is the 'on-premises gateway' option; it dials out and needs no inbound ports.",
        wl: "Power BI semantic models, Dataflow Gen2, pipelines, plus Power Platform", link: "Outbound-only to Azure Relay; ExpressRoute keeps it off the public internet" },
      { color: C.teal, bg: C.tealBg, icon: "FaLock", title: "Managed private endpoint + Private Link Service", where: "Fabric-managed endpoint connects to a Private Link Service in YOUR VNet, fronting an internal load balancer / NAT forwarder.",
        wl: "Fabric Data Engineering (Spark notebooks, job definitions) and Eventstream; Fabric capacity (F / Trial)", link: "ExpressRoute or VPN carries VNet-to-on-prem leg" },
    ];
    for (let i = 0; i < 3; i++) {
      const t = tiles[i], x = 0.3 + i * 4.3, y = 1.6, w = 4.1, h = 3.6;
      s.addShape(pres.shapes.RECTANGLE, { x, y, w, h, fill: { color: t.bg }, line: { color: t.color, width: 1.75 } });
      s.addShape(pres.shapes.RECTANGLE, { x, y, w, h: 0.7, fill: { color: t.color }, line: { color: t.color } });
      s.addShape(pres.shapes.OVAL, { x: x + 0.15, y: y + 0.13, w: 0.44, h: 0.44, fill: { color: C.white }, line: { color: C.white } });
      s.addImage({ data: await ic(t.icon, t.color), x: x + 0.26, y: y + 0.24, w: 0.22, h: 0.22 });
      s.addText(t.title, { x: x + 0.7, y, w: w - 0.8, h: 0.7, fontFace: FONT, fontSize: 13.5, bold: true, color: C.white, valign: "middle", margin: 0 });
      const rows = [["WHERE IT RUNS", t.where], ["WORKLOADS", t.wl], ["ON-PREM LEG", t.link]];
      rows.forEach((r, j) => {
        const ry = y + 0.82 + j * 0.9;
        s.addText([
          { text: r[0], options: { bold: true, fontSize: 9, color: t.color, charSpacing: 1, breakLine: true } },
          { text: r[1], options: { fontSize: 11.5, color: C.ink } },
        ], { x: x + 0.15, y: ry, w: w - 0.3, h: 0.85, fontFace: FONT, valign: "top", margin: 0 });
      });
    }

    s.addShape(pres.shapes.RECTANGLE, { x: 0.3, y: 5.4, w: 12.73, h: 1.4, fill: { color: C.goldBg }, line: { color: C.gold, width: 1.25 } });
    s.addImage({ data: await ic("FaRoute", C.gold), x: 0.5, y: 5.65, w: 0.45, h: 0.45 });
    s.addText([
      { text: "The 4 combinations in this deck", options: { bold: true, fontSize: 12, color: C.gold, breakLine: true } },
      { text: "1  VNet data gateway + ExpressRoute private peering     2  VNet data gateway + Site-to-Site IPsec VPN", options: { fontSize: 11, color: C.ink, breakLine: true } },
      { text: "3  On-premises data gateway (outbound-only, ExpressRoute optional)     4  Managed private endpoint + Private Link Service over ExpressRoute / VPN", options: { fontSize: 11, color: C.ink, breakLine: true } },
      { text: "ExpressRoute and VPN are interchangeable hybrid links for patterns 1, 2 and 4; running both gives failover.", options: { fontSize: 10, italic: true, color: C.muted } },
    ], { x: 1.15, y: 5.45, w: 11.7, h: 1.3, fontFace: FONT, valign: "middle", margin: 0 });
    footer(s, 2, "Pick the connector by workload first, then the hybrid link by bandwidth, SLA and lead time.");
    s.addNotes("Key facts (Microsoft Learn): VNet data gateway supports Dataflow Gen2, pipelines, Copy job, Mirroring, Power BI semantic models and paginated reports; runs on P, F or A4+ capacity (F8+ recommended). Private resources outside Azure require ExpressRoute and/or VPN. Subnet must be delegated to Microsoft.PowerPlatform/vnetaccesslinks. The on-premises data gateway needs outbound TCP 443, 5671-5672, 9350-9354 and no inbound ports; ExpressRoute can keep gateway-to-Azure Relay traffic off the public internet. Managed private endpoints support Spark workloads and Eventstream and require Fabric capacity.");
  }

  // ---------- Pattern slides ----------
  await diagramSlide({
    n: 1, slideNo: 3, title: "VNet Data Gateway over ExpressRoute", subtitle: "Private, high-bandwidth path from Fabric / Power BI to on-premises SQL Server",
    tagline: "ExpressRoute private peering  •  Hub & spoke  •  Managed VNet data gateway", badge: "Fabric / PBI → On-prem SQL", badgeIcon: "FaProjectDiagram",
    left: { ...ON_PREM, nodes: [
      { icon: "FaDatabase", label: "SQL Server (on-prem)", sub: "Private IP, TCP 1433; service account or SQL auth" },
      { icon: "FaShieldAlt", label: "Firewall + DNS", sub: "Allow gateway subnet to 1433; conditional forwarder", accent: C.slate },
      { icon: "FaRoute", label: "Customer edge routers", sub: "Redundant BGP pair to ExpressRoute circuit", accent: C.slate },
    ] },
    link1: { color: C.green, both: true, title: "ExpressRoute", caption: "Private peering over a provider circuit or ExpressRoute Direct; no public internet" },
    mid: { title: "Customer Azure Environment", sub: "Hub & spoke landing zone", nodes: [
      { icon: "FaNetworkWired", label: "ExpressRoute gateway (hub)", sub: "GatewaySubnet; zone-redundant SKU" },
      { icon: "FaExchangeAlt", label: "VNet peering", sub: "Hub allows gateway transit; spoke uses remote gateways" },
      { icon: "FaProjectDiagram", label: "VNet data gateway (spoke)", sub: "Delegated subnet: Microsoft.PowerPlatform/vnetaccesslinks" },
    ] },
    link2: { color: C.blue, dash: "dash", both: true, title: "Microsoft backbone", caption: "Gateway containers injected in your subnet" },
    right: FABRIC([
      { icon: "FaChartBar", label: "Semantic models", sub: "Import / DirectQuery; paginated reports" },
      { icon: "FaCogs", label: "Dataflow Gen2, Pipelines", sub: "Copy job and Mirroring" },
      { icon: "FaKey", label: "Fabric / Premium capacity", sub: "P, F (F8+ advised) or A4+" },
    ]),
    cards: mkCards([
      { title: "Connectivity & Routing", q: "\"How does traffic reach on-prem?\"", bullets: [
        "ExpressRoute circuit lands on the hub ExpressRoute gateway",
        "Spoke peering uses remote gateways; UDR/NSG must not block on-prem prefixes",
        "Deterministic latency; traffic stays off the internet" ], outcome: "Private, predictable path." },
      { title: "Gateway & Identity", q: "\"Who sets up and uses the gateway?\"", bullets: [
        "Register Microsoft.PowerPlatform; delegate a dedicated subnet (5 IPs + 1 per member)",
        "Create gateway in Manage connections and gateways",
        "Admins grant users access to the data source" ], outcome: "Governed, shareable gateway." },
      { title: "DNS & Data Protection", q: "\"How is the data source protected?\"", bullets: [
        "Resolve the SQL FQDN via Azure DNS Private Resolver or forwarder",
        "On-prem firewall allows only the delegated subnet CIDR on 1433",
        "Gateway gives compute isolation and traffic auditing" ], outcome: "Least-privilege network access." },
      { title: "Fit & Watch-outs", q: "\"When should we choose this?\"", bullets: [
        "Best for production: large refreshes and DirectQuery",
        "Region must be supported; VNet, subscription and RG cannot change after creation",
        "Circuit lead time and monthly cost" ], outcome: "Recommended primary pattern." },
    ]),
    footer: "Pattern 1: Production-grade private path for Power BI and Fabric data integration.",
    notes: "Sources: https://learn.microsoft.com/data-integration/vnet/overview ; https://learn.microsoft.com/data-integration/vnet/create-data-gateways ; https://learn.microsoft.com/data-integration/vnet/use-data-gateways-sources-power-bi (scenario 2: private resources outside Azure use ExpressRoute and/or VPNs; traffic stays on the Azure backbone). ExpressRoute bandwidth options 50 Mbps to 10 Gbps via provider, higher with ExpressRoute Direct. Hub/spoke gateway transit settings are standard Azure VNet peering configuration.",
  });

  await diagramSlide({
    n: 2, slideNo: 4, title: "VNet Data Gateway over Site-to-Site VPN", subtitle: "Encrypted IPsec tunnels as a faster, lower-cost route to on-premises SQL Server",
    tagline: "Site-to-Site IPsec / IKE  •  Active-active VPN gateway  •  BGP routing", badge: "Fabric / PBI → On-prem SQL", badgeIcon: "FaProjectDiagram",
    left: { ...ON_PREM, nodes: [
      { icon: "FaDatabase", label: "SQL Server (on-prem)", sub: "Private IP, TCP 1433; service account or SQL auth" },
      { icon: "FaShieldAlt", label: "Firewall + DNS", sub: "Allow gateway subnet to 1433; conditional forwarder", accent: C.slate },
      { icon: "FaLock", label: "VPN device (IKEv2 / IPsec)", sub: "Two devices or tunnels for HA; BGP optional", accent: C.slate },
    ] },
    link1: { color: C.amber, dash: "dash", both: true, title: "IPsec VPN tunnels", caption: "Encrypted tunnels over the internet; limited by VPN SKU" },
    mid: { title: "Customer Azure Environment", sub: "Single VNet or hub & spoke", nodes: [
      { icon: "FaNetworkWired", label: "VPN gateway (active-active)", sub: "GatewaySubnet; zone-redundant SKU; BGP" },
      { icon: "FaRoute", label: "Route tables + NSG", sub: "Learn on-prem prefixes; allow 1433 to SQL" },
      { icon: "FaProjectDiagram", label: "VNet data gateway", sub: "Delegated subnet: Microsoft.PowerPlatform/vnetaccesslinks" },
    ] },
    link2: { color: C.blue, dash: "dash", both: true, title: "Microsoft backbone", caption: "Gateway containers injected in your subnet" },
    right: FABRIC([
      { icon: "FaChartBar", label: "Semantic models", sub: "Import / DirectQuery; paginated reports" },
      { icon: "FaCogs", label: "Dataflow Gen2, Pipelines", sub: "Copy job and Mirroring" },
      { icon: "FaKey", label: "Fabric / Premium capacity", sub: "P, F (F8+ advised) or A4+" },
    ]),
    cards: mkCards([
      { title: "Connectivity & Routing", q: "\"How does traffic reach on-prem?\"", bullets: [
        "Two S2S tunnels from an active-active VPN gateway to the on-prem device",
        "Exchange routes with BGP, or define static prefixes",
        "Can coexist with ExpressRoute as automatic failover" ], outcome: "Fast to stand up; resilient." },
      { title: "Gateway & Identity", q: "\"Who sets up and uses the gateway?\"", bullets: [
        "Same VNet data gateway setup as Pattern 1",
        "Delegated subnet must reach the VPN gateway through routing",
        "Share the data source with Fabric / PBI users" ], outcome: "Identical gateway experience." },
      { title: "DNS & Data Protection", q: "\"How is the data source protected?\"", bullets: [
        "IPsec encrypts the tunnel; keep TLS on the SQL connection too",
        "Private DNS forwarding for on-prem names",
        "Monitor tunnel health with Azure Monitor" ], outcome: "Encrypted, auditable path." },
      { title: "Fit & Watch-outs", q: "\"When should we choose this?\"", bullets: [
        "Best for PoC, small refreshes or an ExpressRoute backup",
        "Internet path means variable latency and throughput",
        "Size the VPN SKU to peak refresh windows" ], outcome: "Low-cost start or failover." },
    ]),
    footer: "Pattern 2: Quickest private route; pair with ExpressRoute for resilience.",
    notes: "Same VNet data gateway mechanics as Pattern 1 with a VPN Gateway in place of the ExpressRoute gateway. Microsoft Learn states private resources outside Azure require ExpressRoute and/or VPNs. Check current VPN Gateway SKU throughput and tunnel limits at https://learn.microsoft.com/azure/vpn-gateway/about-gateway-skus when sizing.",
  });

  await diagramSlide({
    n: 3, slideNo: 5, title: "On-Premises Data Gateway (Outbound-Only)", subtitle: "Gateway runs next to the SQL Server and dials out; no inbound firewall holes",
    tagline: "Gateway cluster on-prem  •  Azure Relay  •  ExpressRoute optional", badge: "Fabric / PBI → On-prem SQL", badgeIcon: "FaServer",
    left: { ...ON_PREM, nodes: [
      { icon: "FaDatabase", label: "SQL Server (on-prem)", sub: "Reached on the local LAN; no Azure routing needed" },
      { icon: "FaServer", label: "Data gateway cluster", sub: "2+ Windows nodes for HA and load balancing", accent: C.slate },
      { icon: "FaShieldAlt", label: "Firewall / proxy", sub: "Outbound 443, 5671-5672, 9350-9354; no inbound", accent: C.slate },
    ] },
    link1: { color: C.blue, dash: "dash", title: "Outbound TLS", caption: "Gateway initiates the connection; ExpressRoute can keep it off the internet" },
    mid: { title: "Microsoft Cloud", sub: "Gateway cloud service", nodes: [
      { icon: "FaExchangeAlt", label: "Azure Relay", sub: "Rendezvous for gateway and service connections" },
      { icon: "FaKey", label: "Gateway cloud service", sub: "Routes queries; credentials stored encrypted" },
      { icon: "FaLock", label: "Optional: Fabric Private Link", sub: "Private endpoints for users over ExpressRoute / VPN", accent: C.green },
    ] },
    link2: { color: C.blue, dash: "dash", both: true, title: "Microsoft backbone", caption: "Inside the Microsoft network" },
    right: FABRIC([
      { icon: "FaChartBar", label: "Semantic models", sub: "Import / DirectQuery; paginated reports" },
      { icon: "FaCogs", label: "Dataflow Gen2, Pipelines", sub: "Also serves Power Platform" },
      { icon: "FaUsers", label: "Users and admins", sub: "Entra ID, role-based data source access" },
    ]),
    cards: mkCards([
      { title: "Connectivity & Routing", q: "\"How does traffic reach on-prem?\"", bullets: [
        "Gateway opens outbound connections to Azure Relay",
        "ExpressRoute keeps gateway-to-service traffic off the public internet",
        "Data source is accessed on the LAN" ], outcome: "No inbound exposure." },
      { title: "Gateway & Identity", q: "\"Who sets up and uses the gateway?\"", bullets: [
        "Install on dedicated servers near SQL; register to the tenant",
        "Cluster nodes for HA; keep the gateway updated",
        "Gateway admins manage data sources and users" ], outcome: "Simple setup, you own the hosts." },
      { title: "Data Protection", q: "\"How is the data source protected?\"", bullets: [
        "Credentials are encrypted and stored by the gateway service",
        "Restrict outbound traffic to required endpoints",
        "Private Link can lock down user access to the service" ], outcome: "Controlled egress." },
      { title: "Fit & Watch-outs", q: "\"When should we choose this?\"", bullets: [
        "Best when no Azure network is wanted, or as a quick start",
        "You patch, size and monitor the gateway servers",
        "No VNet-level traffic auditing or Azure private endpoints" ], outcome: "Lowest network effort." },
    ]),
    footer: "Pattern 3: The on-premises counterpart to the VNet gateway: simple, outbound-only.",
    notes: "Sources: https://learn.microsoft.com/data-integration/gateway/service-gateway-onprem-indepth (traffic goes gateway to Azure Relay to Power BI backend; ExpressRoute ensures it does not traverse the public internet) and the gateway communication settings page (outbound TCP 80, 443, 1433, 5671, 5672, 9350-9354; no inbound ports). Optional inbound Private Link: https://learn.microsoft.com/fabric/security/security-private-links-overview and https://learn.microsoft.com/fabric/enterprise/powerbi/service-security-private-links-on-premises.",
  });

  await diagramSlide({
    n: 4, slideNo: 6, title: "Managed Private Endpoint + Private Link Service", subtitle: "Fabric Spark workloads reach on-premises SQL through your Azure Private Link Service",
    tagline: "Managed private endpoint  •  Private Link Service  •  ExpressRoute / VPN", badge: "Fabric Spark → On-prem SQL", badgeIcon: "FaLock",
    left: { ...ON_PREM, nodes: [
      { icon: "FaDatabase", label: "SQL Server (on-prem)", sub: "Static private IP, TCP 1433" },
      { icon: "FaShieldAlt", label: "Firewall + DNS", sub: "Allow forwarder / PLS NAT IPs to 1433", accent: C.slate },
      { icon: "FaRoute", label: "Existing hybrid edge", sub: "ExpressRoute or Site-to-Site VPN", accent: C.slate },
    ] },
    link1: { color: C.green, both: true, title: "ExpressRoute / VPN", caption: "Private routes between your VNet and the on-prem SQL prefix" },
    mid: { title: "Customer Azure Environment", sub: "Private Link Service VNet", nodes: [
      { icon: "FaNetworkWired", label: "ExpressRoute / VPN gateway", sub: "Terminates the hybrid link in the VNet" },
      { icon: "FaExchangeAlt", label: "Internal LB + NAT forwarder", sub: "DNAT to on-prem SQL; or PLS Direct Connect (preview)" },
      { icon: "FaLock", label: "Private Link Service", sub: "Auto-approve the Fabric tenant; you approve requests", accent: C.green },
    ] },
    link2: { color: C.green, both: true, title: "Private Link", caption: "Microsoft backbone, no public internet" },
    right: FABRIC([
      { icon: "FaLock", label: "Managed private endpoint", sub: "Created by workspace admin via REST API", accent: C.green },
      { icon: "FaCogs", label: "Spark workloads", sub: "Notebooks, job definitions; Eventstream" },
      { icon: "FaKey", label: "Fabric capacity", sub: "F SKU or Trial required" },
    ]),
    cards: mkCards([
      { title: "Connectivity & Routing", q: "\"How does traffic reach on-prem?\"", bullets: [
        "Hybrid link ends in a VNet that hosts the Private Link Service",
        "Standard ILB with NAT forwarder VMs forwards 1433 to on-prem SQL",
        "Direct Connect (preview) can target a static IP without the LB" ], outcome: "Private, gateway-free path." },
      { title: "Fabric & Identity", q: "\"Who creates and approves it?\"", bullets: [
        "Workspace admin creates the endpoint with the Managed Private Endpoints REST API",
        "Network admin approves the pending connection on the PLS",
        "Connect from Spark with the FQDN" ], outcome: "Two-party approval." },
      { title: "Data Protection", q: "\"How is the data source protected?\"", bullets: [
        "Traffic stays on the Microsoft backbone",
        "NSGs limit 1433 to the forwarders; admin ports only from trusted ranges",
        "Use customer-managed keys for data at rest" ], outcome: "Isolated, approved access." },
      { title: "Fit & Watch-outs", q: "\"When should we choose this?\"", bullets: [
        "Best for Spark and lakehouse ingestion without a gateway",
        "You run the NAT VMs, or accept a preview feature",
        "Not for semantic models or paginated reports" ], outcome: "Complements Patterns 1 or 2." },
    ]),
    footer: "Pattern 4: Gateway-free private path for Fabric Data Engineering workloads.",
    notes: "Source: https://learn.microsoft.com/fabric/security/connect-to-on-premise-sources-using-managed-private-endpoints (Private Link Service, Standard Load Balancer, NAT forwarder or PLS Direct Connect preview; REST API for creation; approval on the PLS). Overview and limitations: https://learn.microsoft.com/fabric/security/security-managed-private-endpoints-overview (Spark and Eventstream item types; Fabric capacities only; FQDN via Private Link Service supported only with the REST API; wait at least 15 minutes after deleting before recreating).",
  });

  // ---------- Slide 7: Comparison ----------
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    s.addText("Side-by-side comparison", { x: 0.3, y: 0.2, w: 12.7, h: 0.6, fontFace: FONT, fontSize: 27, bold: true, color: C.navy, align: "center", margin: 0 });
    s.addText("Pick by workload, operational ownership and bandwidth needs", { x: 0.3, y: 0.78, w: 12.7, h: 0.35, fontFace: FONT, fontSize: 13, bold: true, color: C.slate, align: "center", margin: 0 });
    const hd = (t, col) => ({ text: t, options: { bold: true, color: C.white, fill: { color: col }, align: "center", valign: "middle", fontSize: 11 } });
    const lab = (t) => ({ text: t, options: { bold: true, color: C.navy, fill: { color: C.blueBg }, valign: "middle", fontSize: 10.5 } });
    const cell = (t) => ({ text: t, options: { color: C.ink, valign: "middle", fontSize: 10.5 } });
    const rows = [
      [{ text: "", options: { fill: { color: C.white } } }, hd("1  VNet GW + ExpressRoute", C.blue), hd("2  VNet GW + S2S VPN", C.amber), hd("3  On-prem data gateway", C.slate), hd("4  Managed PE + PLS", C.teal)],
      [lab("Hybrid link"), cell("ExpressRoute private peering"), cell("IPsec VPN over internet"), cell("Outbound 443 / AMQP to Azure Relay; ExpressRoute optional"), cell("ExpressRoute or VPN to PLS VNet")],
      [lab("Connector runs in"), cell("Your Azure VNet (Microsoft-managed)"), cell("Your Azure VNet (Microsoft-managed)"), cell("Your on-prem servers"), cell("Fabric managed VNet to your Private Link Service")],
      [lab("Workloads"), cell("Semantic models, paginated, Dataflow Gen2, pipelines, Copy job, Mirroring"), cell("Same as pattern 1"), cell("Semantic models, Dataflow Gen2, pipelines, Power Platform"), cell("Spark notebooks and job definitions, Eventstream")],
      [lab("Public internet"), cell("None"), cell("Encrypted tunnel crosses internet"), cell("Outbound only; none with ExpressRoute"), cell("None")],
      [lab("You operate"), cell("ExpressRoute circuit, hub and spoke, gateway subnet"), cell("VPN devices, VPN gateway, subnet"), cell("Gateway servers, patching, cluster"), cell("ILB and NAT VMs (or preview), approvals")],
      [lab("Main watch-out"), cell("Lead time and cost; supported regions"), cell("Variable latency and throughput"), cell("Hardware sizing; no VNet-level audit"), cell("REST-only steps; not for semantic models")],
      [lab("Best fit"), cell("Production, high volume"), cell("PoC or backup path"), cell("Quick start, no Azure network"), cell("Spark ingestion, gateway-free")],
    ];
    s.addTable(rows, { x: 0.3, y: 1.3, w: 12.73, colW: [1.73, 2.75, 2.75, 2.75, 2.75], fontFace: FONT, border: { type: "solid", color: C.line, pt: 1 }, rowH: [0.5, 0.62, 0.62, 0.9, 0.62, 0.8, 0.7, 0.6], margin: [0.04, 0.08, 0.04, 0.08] });
    footer(s, 7, "Patterns can be combined: for example 1 for Power BI and pipelines, plus 4 for Spark.");
    s.addNotes("Comparison derived from Microsoft Learn documentation cited on the pattern slides.");
  }

  // ---------- Slide 8: Recommendation ----------
  {
    const s = pres.addSlide();
    s.background = { color: C.navy };
    s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 0.35, h: 7.5, fill: { color: C.teal }, line: { color: C.teal } });
    s.addText("Recommended approach and next steps", { x: 0.9, y: 0.45, w: 11.8, h: 0.7, fontFace: FONT, fontSize: 32, bold: true, color: C.white, margin: 0 });
    const left = [
      ["Primary", "Pattern 1: VNet data gateway over ExpressRoute for Power BI semantic models and Fabric data integration.", C.blue],
      ["Resilience", "Pattern 2: add a Site-to-Site VPN on the same VNet as an ExpressRoute failover, or as the PoC path.", C.amber],
      ["Spark ingestion", "Pattern 4: managed private endpoint + Private Link Service on the same hybrid link.", C.teal],
      ["Fallback", "Pattern 3: on-premises data gateway when Azure networking is not yet ready.", C.slate],
    ];
    left.forEach((r, i) => {
      const y = 1.45 + i * 1.3;
      s.addShape(pres.shapes.RECTANGLE, { x: 0.9, y, w: 6.2, h: 1.1, fill: { color: "16397F" }, line: { color: r[2], width: 2 } });
      s.addShape(pres.shapes.RECTANGLE, { x: 0.9, y, w: 0.12, h: 1.1, fill: { color: r[2] }, line: { color: r[2] } });
      s.addText([
        { text: r[0], options: { bold: true, fontSize: 13, color: "CADCFC", breakLine: true } },
        { text: r[1], options: { fontSize: 11.5, color: C.white } },
      ], { x: 1.2, y, w: 5.8, h: 1.1, fontFace: FONT, valign: "middle", margin: 0 });
    });
    s.addText("Next steps", { x: 7.6, y: 1.4, w: 5.2, h: 0.4, fontFace: FONT, fontSize: 18, bold: true, color: C.white, margin: 0 });
    const steps = [
      "Confirm workloads: semantic models, Dataflow Gen2, pipelines, Spark",
      "Confirm Fabric region and an Azure region on the VNet gateway supported list",
      "Choose ExpressRoute circuit, VPN, or both, and size bandwidth",
      "Design hub and spoke, delegated subnet, DNS and firewall rules",
      "Pilot with one on-prem SQL source and validate refresh, DNS and failover",
    ];
    s.addText(steps.map((t, i) => ({ text: t, options: { bullet: { type: "number" }, breakLine: i < steps.length - 1, paraSpaceAfter: 8 } })),
      { x: 7.6, y: 1.85, w: 5.2, h: 3.6, fontFace: FONT, fontSize: 13, color: C.white, valign: "top", margin: 0 });
    s.addText("Sources: Microsoft Learn - What is a virtual network data gateway; Create virtual network data gateways; Use virtual network data gateway and data sources in Power BI; Connect to on-premises data sources using managed private endpoints; Overview of managed private endpoints for Fabric; On-premises data gateway architecture; ExpressRoute circuits and peering.",
      { x: 0.9, y: 6.55, w: 11.9, h: 0.7, fontFace: FONT, fontSize: 10, color: "9DB4E8", valign: "top", margin: 0 });
    s.addNotes("Recommendation is a starting point; validate against Fabric region, bandwidth, security and operations requirements.");
  }

  await pres.writeFile({ fileName: "Fabric-PBI-OnPrem-Private-Connectivity.pptx" });
  console.log("written");
}

main().catch((e) => { console.error(e); process.exit(1); });
