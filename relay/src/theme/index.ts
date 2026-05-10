import { extendTheme } from "@mui/material/styles";
import { lightPalette, darkPalette } from "./palette";
import { typography } from "./typography";
import { components } from "./components";

export const theme = extendTheme({
  cssVarPrefix: "mui",
  colorSchemes: {
    light: { palette: lightPalette },
    dark: { palette: darkPalette },
  },
  shape: { borderRadius: 12 },
  typography,
  components,
});

export default theme;
