import type { Metadata } from "next";
import MainNavigationDrawer from "../../components/main-navigation-drawer";

export const metadata: Metadata = {
  title: "AI Accountant | Overview",
  description: "The standalone Overview section of AI Accountant.",
};

/** Overview is a separate section. Product dashboards live under Product. */
export default function OverviewPage() {
  return (
    <>
      <header className="app-header product-metrics-header">
        <div className="brand-left">
          <div className="brand">
            <MainNavigationDrawer />
            AI Accountant
          </div>
          <span className="brand-divider" />
          <span className="product-name">Overview</span>
        </div>
      </header>
      <main aria-label="Overview" style={{ minHeight: "calc(100dvh - 56px)" }} />
    </>
  );
}
