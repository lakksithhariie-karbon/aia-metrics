import type { Metadata } from "next";
import CustomerDashboard from "../../components/customer/customer-dashboard";
import "./customer.css";

export const metadata: Metadata = {
  title: "AI Accountant | Customer",
  description: "Customer-wise module usage with nested user contributions.",
};

export default function CustomerPage() {
  return <CustomerDashboard />;
}
