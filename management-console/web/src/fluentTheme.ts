import {
  createLightTheme,
  createDarkTheme,
  type BrandVariants,
  type Theme,
} from "@fluentui/react-components";

// Azure-aligned brand ramp anchored on #0078d4 (azure-mid).
// Hand-tuned to match the SMB Ready Foundations docs site palette.
const azureBrand: BrandVariants = {
  10: "#020509",
  20: "#0a1424",
  30: "#0a2540",
  40: "#0c2f54",
  50: "#0d3c6e",
  60: "#0e4a86",
  70: "#0e589f",
  80: "#0078d4",
  90: "#1f8be0",
  100: "#3a9be8",
  110: "#50a9ef",
  120: "#71baf3",
  130: "#92ccf6",
  140: "#b4ddf9",
  150: "#d1e7f7",
  160: "#ecf4fb",
};

export const lightTheme: Theme = {
  ...createLightTheme(azureBrand),
};

export const darkTheme: Theme = {
  ...createDarkTheme(azureBrand),
};
