"use client";

import MuiStack, { type StackProps as MuiStackProps } from "@mui/material/Stack";
import type { CSSProperties } from "react";
import type { SxProps, Theme } from "@mui/material/styles";

type LayoutProp =
  | string
  | number
  | { [key: string]: string | number | undefined };

interface StackProps extends MuiStackProps {
  justifyContent?: LayoutProp | CSSProperties["justifyContent"];
  alignItems?: LayoutProp | CSSProperties["alignItems"];
  flexWrap?: LayoutProp | CSSProperties["flexWrap"];
}

export function Stack({
  justifyContent,
  alignItems,
  flexWrap,
  sx,
  ...rest
}: StackProps) {
  const layout: Record<string, unknown> = {};
  if (justifyContent !== undefined) layout.justifyContent = justifyContent;
  if (alignItems !== undefined) layout.alignItems = alignItems;
  if (flexWrap !== undefined) layout.flexWrap = flexWrap;
  const mergedSx = (Object.keys(layout).length > 0
    ? sx
      ? [layout, ...(Array.isArray(sx) ? sx : [sx])]
      : [layout]
    : sx) as SxProps<Theme>;
  return <MuiStack {...rest} sx={mergedSx} />;
}

export type { StackProps };
