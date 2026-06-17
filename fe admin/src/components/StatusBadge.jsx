export default function StatusBadge({ value }) {
  const normalized = String(value || 'UNKNOWN').toLowerCase();
  return <span className={`status status-${normalized}`}>{value}</span>;
}
