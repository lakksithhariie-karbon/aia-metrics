import type { Metadata } from "next";
import { Oxanium } from "next/font/google";
import "./prototype.css";

const oxanium = Oxanium({
  subsets: ["latin"],
  weight: ["200", "300", "400", "500", "600", "700", "800"],
  variable: "--font-oxanium",
  display: "swap",
});

export const metadata: Metadata = {
  title: "AI Accountant | Product Overview",
  description: "Product metrics UI foundation",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${oxanium.variable} ${oxanium.className}`}>
      <body className={oxanium.className}>{children}</body>
    </html>
  );
}
