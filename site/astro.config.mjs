import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import starlightLinksValidator from "starlight-links-validator";

export default defineConfig({
  site: "https://jonathan-vella.github.io",
  base: "/azure-smb-rf",
  trailingSlash: "always",
  integrations: [
    starlight({
      title: "SMB Ready Foundation",
      description:
        "Cost-optimized Azure landing zone for SMB VMware-to-Azure migrations. Hub-spoke networking, 33 governance policies, 4 deployment scenarios.",
      favicon: "/images/favicon.svg",
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
          errorOnRelativeLinks: false,
          errorOnInvalidHashes: false,
        }),
      ],
      sidebar: [
        {
          label: "Getting Started",
          collapsed: true,
          items: [
            { label: "Prerequisites", slug: "getting-started/prerequisites" },
            { label: "Quick Start", slug: "getting-started/quick-start" },
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
            { label: "FAQ", slug: "reference/faq" },
          ],
        },
        {
          label: "CI/CD",
          collapsed: true,
          badge: { text: "Soon", variant: "caution" },
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
