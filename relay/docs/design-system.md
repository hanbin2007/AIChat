Design 复用方案

本项目的视觉风格不是靠零散 CSS 堆出来的，而是由 **一份 MUI 主题 + 一组组件约定** 派生。把这两部分搬到任何 Next.js / React 项目都能立刻得到同款观感。

## 1. 依赖

```json
{
  "@mui/material": "^7",
  "@mui/icons-material": "^7",
  "@emotion/react": "^11",
  "@emotion/styled": "^11",
  "@emotion/cache": "^11",
  "@mui/material-nextjs": "^7"
}
```

字体（通过 `next/font` 注入即可，不要从 CDN 引）：

- 正文：`Noto Sans SC`（400 / 500 / 700）
- 数字 / 代码：`IBM Plex Mono`
- 图标：`@mui/icons-material` 的 **Rounded** 系列（圆头线条与 8px 圆角呼应）

## 2. 设计 Token

| 类别 | Token | 值 |
| --- | --- | --- |
| 主色 | `primary.main` | `#0f766e`（teal 700） |
| 主色暗 | `primary.dark` | `#115e59` |
| 主色亮 | `primary.light` | `#5eead4` |
| 次色 | `secondary.main` | `#2563eb` |
| 背景 | `background.default` | `#eef3f9` |
| 卡面 | `background.paper` | `#ffffff` |
| 成功 / 警告 / 错误 | `success/warning/error.main` | `#2e7d32` / `#c77700` / `#b3261e` |
| 主文字 | `text.primary` | `#102a43` |
| 次文字 | `text.secondary` | `#52667a` |
| 圆角基准 | `shape.borderRadius` | `8`（Dialog 升到 `16`） |
| 卡片描边 | — | `1px solid rgba(16, 42, 67, 0.08)` |
| 卡片阴影 | — | `0 24px 48px rgba(15, 23, 42, 0.05)` |

**配色思路**：teal 主色 + blue 次色，冷调克制；背景不是纯白，而是 radial + linear 双层渐变，避免"扁"的廉价感。

## 3. 主题文件（直接复制）

```ts
// src/theme/theme.ts
"use client";

import { alpha, createTheme } from "@mui/material/styles";

export const appTheme = createTheme({
  cssVariables: { colorSchemeSelector: "class" },
  colorSchemes: { light: true },
  shape: { borderRadius: 8 },
  palette: {
    mode: "light",
    primary:   { main: "#0f766e", dark: "#115e59", light: "#5eead4" },
    secondary: { main: "#2563eb" },
    background:{ default: "#eef3f9", paper: "#ffffff" },
    success:   { main: "#2e7d32" },
    warning:   { main: "#c77700" },
    error:     { main: "#b3261e" },
    text:      { primary: "#102a43", secondary: "#52667a" },
  },
  typography: {
    fontFamily: 'var(--font-body), "Noto Sans SC", sans-serif',
    h1: { fontWeight: 700, letterSpacing: "-0.03em" },
    h2: { fontWeight: 700, letterSpacing: "-0.02em" },
    h3: { fontWeight: 700, letterSpacing: "-0.02em" },
    h4: { fontWeight: 700 },
    button: { textTransform: "none", fontWeight: 600 },
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: (theme) => ({
        html: { height: "100%", colorScheme: "light only" },
        body: {
          minHeight: "100%",
          background: `
            radial-gradient(circle at top left, ${alpha(theme.palette.primary.light, 0.15)}, transparent 30%),
            linear-gradient(180deg, #f7f9fc 0%, #eef3f9 100%)
          `,
          backgroundAttachment: "fixed",
        },
      }),
    },
    MuiPaper: {
      defaultProps: { elevation: 0 },
      styleOverrides: { root: { backgroundImage: "none" } },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          border: "1px solid rgba(16, 42, 67, 0.08)",
          boxShadow: "0 24px 48px rgba(15, 23, 42, 0.05)",
        },
      },
    },
    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: { root: { borderRadius: 8 } },
    },
    MuiChip: { styleOverrides: { root: { borderRadius: 8 } } },
    MuiDrawer: {
      styleOverrides: {
        paper: {
          borderRight: "1px solid rgba(16, 42, 67, 0.08)",
          backgroundColor: "rgba(255, 255, 255, 0.92)",
          backdropFilter: "blur(18px)",
        },
      },
    },
    MuiDialog: { styleOverrides: { paper: { borderRadius: 16 } } },
    MuiTableCell: { styleOverrides: { head: { fontWeight: 700 } } },
    MuiTextField: { defaultProps: { fullWidth: true, variant: "outlined" } },
  },
});
```

## 4. Provider 与字体接线

```tsx
// src/components/mui-providers.tsx
"use client";

import { AppRouterCacheProvider } from "@mui/material-nextjs/v15-appRouter";
import { CssBaseline, ThemeProvider } from "@mui/material";
import { appTheme } from "@/theme/theme";

export function MuiProviders({ children }: { children: React.ReactNode }) {
  return (
    <AppRouterCacheProvider>
      <ThemeProvider theme={appTheme}>
        <CssBaseline />
        {children}
      </ThemeProvider>
    </AppRouterCacheProvider>
  );
}
```

```tsx
// src/app/layout.tsx
import { Noto_Sans_SC, IBM_Plex_Mono } from "next/font/google";

const body = Noto_Sans_SC({
  subsets: ["latin"], weight: ["400", "500", "700"], variable: "--font-body",
});
const mono = IBM_Plex_Mono({
  subsets: ["latin"], weight: ["400", "500", "700"], variable: "--font-mono",
});

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN" className={`${body.variable} ${mono.variable}`}>
      <body><MuiProviders>{children}</MuiProviders></body>
    </html>
  );
}
```

## 5. 组件使用约定

- **不写 className**，统一用 `sx` 消费 token：`color="text.secondary"`、`bgcolor="background.paper"`、`p={{ xs: 2, md: 3 }}`。
- **间距走 8px 网格**：所有 `p`/`m`/`gap` 用整数（`1` = 8px），不要写 `padding: "10px"`。
- **响应式优先用 sx 断点对象**，而不是写 media query。
- **图标只用 `*Rounded`**：`EditRounded`、`CheckCircleRounded`、`MenuRounded`，保持线条风格统一。
- **数字 / ID / 分数** 套 `fontFamily="var(--font-mono)"`，强化数据感。
- **Card / Paper 不要再加阴影**，主题已经给了；要强调时用主色描边而不是加深阴影。
- **按钮不写图标 + 文字的全大写**，`textTransform: "none"` 已默认。
- **Dialog / Drawer / Snackbar** 直接用 MUI 组件，毛玻璃 / 圆角已在主题里 override。

## 6. 反例

- ❌ 直接写 `style={{ background: "#fff", borderRadius: 8 }}` —— 绕开了主题。
- ❌ 用 `Box sx={{ boxShadow: 4 }}` —— MUI 默认阴影偏拟物，本系统应保持 `elevation: 0` + 卡片描边。
- ❌ 引入第三方图标库（lucide / tabler）混搭 —— 风格不统一。
- ❌ 给 Button 自己加 gradient / 内阴影 —— 违背"克制"基调。

## 7. 拓展建议

- 暗色模式：在 `colorSchemes` 加 `dark: { palette: { ... } }`，把背景渐变换成深色基础；`cssVariables.colorSchemeSelector: "class"` 已为切换做好准备。
- 主题色替换：只改 `palette.primary` / `secondary`，其余组件 override 不动即可换肤。
- 密度：表格 / 列表密集场景用 `<Table size="small">`，不要去改全局 spacing。
