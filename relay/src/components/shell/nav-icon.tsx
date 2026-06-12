"use client";

import type { ComponentType } from "react";
import type { SvgIconProps } from "@mui/material/SvgIcon";
import DashboardRounded from "@mui/icons-material/DashboardRounded";
import CableRounded from "@mui/icons-material/CableRounded";
import ForumRounded from "@mui/icons-material/ForumRounded";
import GroupRounded from "@mui/icons-material/GroupRounded";
import PaymentsRounded from "@mui/icons-material/PaymentsRounded";
import QueryStatsRounded from "@mui/icons-material/QueryStatsRounded";
import AutoAwesomeRounded from "@mui/icons-material/AutoAwesomeRounded";
import SettingsRounded from "@mui/icons-material/SettingsRounded";
import MenuBookRounded from "@mui/icons-material/MenuBookRounded";
import InfoRounded from "@mui/icons-material/InfoRounded";

const ICONS: Record<string, ComponentType<SvgIconProps>> = {
  Dashboard: DashboardRounded,
  Cable: CableRounded,
  Forum: ForumRounded,
  Group: GroupRounded,
  Payments: PaymentsRounded,
  QueryStats: QueryStatsRounded,
  AutoAwesome: AutoAwesomeRounded,
  Settings: SettingsRounded,
  MenuBook: MenuBookRounded,
  Info: InfoRounded,
};

export function NavIcon({ name, ...rest }: { name: string } & SvgIconProps) {
  const Component = ICONS[name] ?? DashboardRounded;
  return <Component {...rest} />;
}
