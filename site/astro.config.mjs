import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import starlightLinksValidator from "starlight-links-validator";
import rehypeMermaid from "rehype-mermaid-lite";

export default defineConfig({
  site: "https://jonathan-vella.github.io",
  base: "/azure-smb-rf",
  trailingSlash: "always",
  markdown: {
    rehypePlugins: [rehypeMermaid],
  },
  integrations: [
    starlight({
      title: "SMB Ready Foundation",
      description:
        "Cost-optimized Azure landing zone for SMB VMware-to-Azure migrations. Hub-spoke networking, governance policies, 4 deployment scenarios.",
      favicon: "/images/favicon.svg",
      head: [
        {
          tag: "meta",
          attrs: {
            property: "og:image",
            content:
              "https://jonathan-vella.github.io/azure-smb-rf/images/architecture-baseline.png",
          },
        },
        {
          tag: "meta",
          attrs: { property: "og:type", content: "website" },
        },
        {
          tag: "meta",
          attrs: { name: "twitter:card", content: "summary_large_image" },
        },
      ],
      editLink: {
        baseUrl:
          "https://github.com/jonathan-vella/azure-smb-rf/edit/main/site/",
      },
      lastUpdated: true,
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/jonathan-vella/azure-smb-rf",
        },
      ],
      customCss: [
        "@fontsource/space-grotesk/400.css",
        "@fontsource/space-grotesk/700.css",
        "@fontsource/manrope/400.css",
        "@fontsource/manrope/700.css",
        "@fontsource/ibm-plex-mono/400.css",
        "./src/styles/custom.css",
      ],
      expressiveCode: {
        styleOverrides: { borderRadius: "0.5rem" },
      },
      plugins: [
        starlightLinksValidator({
          errorOnRelativeLinks: true,
          errorOnInvalidHashes: false,
        }),
      ],
      sidebar: [
        {
          label: "Getting Started",
          collapsed: true,
          items: [
            {
              label: "What Is SMB Ready Foundation?",
              slug: "getting-started/what-is-smb-rf",
            },
            { label: "Prerequisites", slug: "getting-started/prerequisites" },
            { label: "Quick Start", slug: "getting-started/quick-start" },
            {
              label: "Partner Onboarding",
              slug: "getting-started/partner-onboarding",
            },
          ],
        },
        {
          label: "Deploying",
          collapsed: true,
          items: [
            {
              label: "Deployment Scenarios & Costs",
              slug: "deploying/scenarios",
            },
            {
              label: "Step-by-Step Walkthrough",
              slug: "deploying/walkthrough",
            },
            {
              label: "Terraform Track",
              slug: "deploying/terraform-track",
            },
            {
              label: "Configuration & Parameters",
              slug: "deploying/configuration",
            },
            {
              label: "Management Group & Policies",
              slug: "deploying/management-group",
            },
          ],
        },
        {
          label: "Operating",
          collapsed: true,
          items: [
            { label: "Operations Runbook", slug: "operating/runbook" },
            { label: "Monitoring & Alerts", slug: "operating/monitoring" },
            {
              label: "Backup & Disaster Recovery",
              slug: "operating/backup-dr",
            },
            { label: "Cost Management", slug: "operating/cost-management" },
            {
              label: "Compliance Matrix",
              slug: "operating/compliance-matrix",
            },
            { label: "Customization", slug: "operating/customization" },
            { label: "Teardown & Cleanup", slug: "operating/teardown" },
            { label: "Troubleshooting", slug: "operating/troubleshooting" },
          ],
        },
        {
          label: "Reference",
          collapsed: true,
          items: [
            {
              label: "Architecture Diagrams",
              slug: "reference/architecture",
            },
            { label: "Resource Inventory", slug: "reference/resources" },
            { label: "Policy Catalog", slug: "reference/policies" },
            { label: "Cost Comparison", slug: "reference/costs" },
            { label: "Bicep Modules", slug: "reference/bicep-modules" },
            {
              label: "Terraform Modules",
              slug: "reference/terraform-modules",
            },
            {
              label: "Design Decisions (ADRs)",
              slug: "reference/design-decisions",
            },
            {
              label: "Partner Quick Reference",
              slug: "reference/partner-quick-reference",
            },
            { label: "FAQ", slug: "reference/faq" },
          ],
        },
        {
          label: "Reference — ADRs",
          collapsed: true,
          items: [
            {
              label: "ADR-0001: Cost-Optimized Architecture",
              slug: "reference/adr/adr-0001",
            },
            {
              label: "ADR-0002: Bicep Implementation",
              slug: "reference/adr/adr-0002",
            },
            {
              label: "ADR-0003: AVM Firewall Migration",
              slug: "reference/adr/adr-0003",
            },
            {
              label: "ADR-0004: Deployment Ordering",
              slug: "reference/adr/adr-0004",
            },
            {
              label: "ADR-0005: Terraform Dual-Track",
              slug: "reference/adr/adr-0005",
            },
            {
              label: "ADR-0006: Single-Root Composition",
              slug: "reference/adr/adr-0006",
            },
          ],
        },
        {
          label: "CI/CD",
          collapsed: true,
          items: [{ label: "Overview", slug: "cicd/overview" }],
        },
        {
          label: "Project",
          collapsed: true,
          items: [
            { label: "Contributing", slug: "project/contributing" },
            { label: "Changelog", slug: "project/changelog" },
          ],
        },
      ],
    }),
  ],
});
