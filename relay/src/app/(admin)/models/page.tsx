import Link from "next/link";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Chip from "@mui/material/Chip";
import { AppShell } from "@/components/shell/app-shell";
import { DEFAULT_MODELS } from "@/lib/gemini/models";

export const dynamic = "force-dynamic";

export default function ModelsPage() {
  return (
    <AppShell
      title="模型"
      breadcrumb={[{ label: "AIChat Relay", href: "/dashboard" }, { label: "模型" }]}
    >
      <Box
        sx={{
          display: "grid",
          gridTemplateColumns: {
            xs: "1fr",
            md: "repeat(2, 1fr)",
            xl: "repeat(3, 1fr)",
          },
          gap: 2,
        }}
      >
        {DEFAULT_MODELS.map((m) => (
          <Card key={m.id}>
            <CardContent>
              <Stack spacing={1.5}>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>
                    {m.displayName}
                  </Typography>
                  <Typography
                    variant="caption"
                    color="text.secondary"
                    sx={{ fontFamily: "var(--font-mono)", display: "block" }}
                  >
                    {m.id}
                  </Typography>
                </Box>
                <Box>
                  <Typography variant="caption" color="text.secondary">
                    家族
                  </Typography>
                  <Typography variant="body2">{m.family}</Typography>
                </Box>
                <Box>
                  <Typography variant="caption" color="text.secondary">
                    能力
                  </Typography>
                  <Stack direction="row" spacing={0.5} flexWrap="wrap" sx={{ mt: 0.5, gap: 0.5 }}>
                    {m.capabilities.thinking ? (
                      <Chip size="small" label="思考" color="primary" />
                    ) : null}
                    {m.capabilities.search ? <Chip size="small" label="搜索" /> : null}
                    {m.capabilities.codeExecution ? (
                      <Chip size="small" label="代码执行" />
                    ) : null}
                    {m.capabilities.audio ? <Chip size="small" label="音频" /> : null}
                    {m.capabilities.vision ? <Chip size="small" label="视觉" /> : null}
                  </Stack>
                </Box>
                <Box>
                  <Typography variant="caption" color="text.secondary">
                    强度档位
                  </Typography>
                  <Stack direction="row" spacing={0.5} flexWrap="wrap" sx={{ mt: 0.5, gap: 0.5 }}>
                    {m.supportedIntensities.map((i) => (
                      <Chip key={i} size="small" label={i} variant="outlined" />
                    ))}
                  </Stack>
                </Box>
                <Box>
                  <Typography
                    component={Link}
                    href="/billing"
                    variant="body2"
                    sx={{ color: "primary.main", textDecoration: "none", fontWeight: 600 }}
                  >
                    在 Billing Studio 中编辑计价 →
                  </Typography>
                </Box>
              </Stack>
            </CardContent>
          </Card>
        ))}
      </Box>
    </AppShell>
  );
}
