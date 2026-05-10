import * as React from "react";
import DashboardIcon from "@mui/icons-material/Dashboard";
import CableIcon from "@mui/icons-material/Cable";
import ForumIcon from "@mui/icons-material/Forum";
import GroupsIcon from "@mui/icons-material/Groups";
import PaymentsIcon from "@mui/icons-material/Payments";
import MonitoringIcon from "@mui/icons-material/MonitorHeart";
import HubIcon from "@mui/icons-material/Hub";
import SettingsIcon from "@mui/icons-material/Settings";
import MenuBookIcon from "@mui/icons-material/MenuBook";
import InfoIcon from "@mui/icons-material/Info";
import type { SvgIconProps } from "@mui/material/SvgIcon";

const ICON_MAP: Record<string, React.ComponentType<SvgIconProps>> = {
  Dashboard: DashboardIcon,
  Cable: CableIcon,
  Forum: ForumIcon,
  Groups: GroupsIcon,
  Payments: PaymentsIcon,
  Monitoring: MonitoringIcon,
  Hub: HubIcon,
  Settings: SettingsIcon,
  MenuBook: MenuBookIcon,
  Info: InfoIcon,
};

export function NavIcon({ name, ...props }: { name: string } & SvgIconProps) {
  const Component = ICON_MAP[name] ?? InfoIcon;
  return <Component {...props} />;
}
