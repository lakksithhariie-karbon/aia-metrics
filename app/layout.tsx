import type { Metadata } from "next";
import "./prototype.css";
export const metadata: Metadata = { title: "AI Accountant | Product Overview", description: "Product metrics UI foundation" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
