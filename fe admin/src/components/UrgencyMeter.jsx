// 1-5 urgency meter. We render 5 little pips; filled pips
// change colour depending on the value so admins can scan a list
// of cards and instantly see which ones to look at first.
export default function UrgencyMeter({ value }) {
  const safe = Math.max(0, Math.min(5, Number(value) || 0));
  let tone = 'urgency-low';
  if (safe >= 4) tone = 'urgency-high';
  else if (safe >= 2) tone = 'urgency-medium';

  return (
    <span
      className={`urgency-meter ${tone}`}
      title={`Urgency ${safe} of 5`}
      aria-label={`Urgency ${safe} of 5`}
    >
      <span className="urgency-label">U{safe}</span>
      <span className="urgency-pips">
        {[1, 2, 3, 4, 5].map((pip) => (
          <span
            key={pip}
            className={`urgency-pip ${pip <= safe ? 'urgency-pip-on' : ''}`}
          />
        ))}
      </span>
    </span>
  );
}
