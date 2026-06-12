"use client";

import { useEffect, useState } from "react";
import { useColorScheme } from "@mui/material/styles";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import LightModeRounded from "@mui/icons-material/LightModeRounded";
import DarkModeRounded from "@mui/icons-material/DarkModeRounded";
import SettingsBrightnessRounded from "@mui/icons-material/SettingsBrightnessRounded";

export function ColorSchemeToggle() {
  const { mode, setMode } = useColorScheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) {
    return (
      <IconButton aria-label="切换主题" disabled>
        <SettingsBrightnessRounded />
      </IconButton>
    );
  }

  const next = mode === "light" ? "dark" : mode === "dark" ? "system" : "light";
  const label =
    mode === "light"
      ? "切换到深色模式"
      : mode === "dark"
        ? "切换到跟随系统"
        : "切换到浅色模式";

  return (
    <Tooltip title={label}>
      <IconButton aria-label={label} onClick={() => setMode(next)}>
        {mode === "light" ? (
          <LightModeRounded />
        ) : mode === "dark" ? (
          <DarkModeRounded />
        ) : (
          <SettingsBrightnessRounded />
        )}
      </IconButton>
    </Tooltip>
  );
}
