import type { Metadata } from "next";
import CompaniesDashboard from "../../components/companies/companies-dashboard";
import "./customer.css";
import "../metrics-page-grid.css";

export const metadata: Metadata = {
  title: "AI Accountant | Companies",
  description: "Company and user module usage from the product event warehouse.",
};

export default function CustomerPage() {
  return <CompaniesDashboard />;
}
