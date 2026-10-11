/** Pure, testable scope guards for Retention's date-range data and loading. */
export type ScopedValue<T> = { key: string; value: T };
export type ScopedRequest = { key: string; pending: boolean };

/** Never show a previously loaded period beneath another period's label. */
export function visibleScopedValue<T>(
  selectedKey: string,
  record: ScopedValue<T> | null,
): T | null {
  return record?.key === selectedKey ? record.value : null;
}

/** The render immediately after changing ranges is pending, before effects run. */
export function isScopedRequestPending(
  selectedKey: string,
  request: ScopedRequest,
): boolean {
  return request.key !== selectedKey || request.pending;
}
