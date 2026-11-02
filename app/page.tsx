import { redirect } from "next/navigation";

/** Send visitors straight to the live Product dashboard; Overview remains available at /overview. */
export default function Home() {
  redirect("/product");
}
