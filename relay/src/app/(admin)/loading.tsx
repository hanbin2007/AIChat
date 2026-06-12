import LinearProgress from "@mui/material/LinearProgress";
import Box from "@mui/material/Box";

export default function Loading() {
  return (
    <Box sx={{ position: "relative", minHeight: 200 }}>
      <LinearProgress
        sx={{
          position: "absolute",
          top: -24,
          left: -24,
          right: -24,
          height: 2,
        }}
      />
    </Box>
  );
}
