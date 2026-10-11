/** Reset the toolbar's filters without changing the sprint reporting scope. */
export function resetAssigneeToolbarFilters(params: URLSearchParams): string {
  const next = new URLSearchParams(params);
  next.delete("module");
  next.delete("sub_module");
  next.delete("severity");
  const query = next.toString();
  return "/delivery/assignees" + (query ? "?" + query : "");
}
