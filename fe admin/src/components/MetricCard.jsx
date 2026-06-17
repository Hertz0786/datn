export default function MetricCard({ label, value, trend, tone }) {
  return (
    <article className={`metric metric-${tone}`}>
      <div>
        <p>{label}</p>
        <strong>{value}</strong>
      </div>
      <span>{trend}</span>
    </article>
  );
}
