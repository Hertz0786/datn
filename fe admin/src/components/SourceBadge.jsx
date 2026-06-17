// Visual distinction between a real user report and an
// auto-flagged blocked attempt. AUTO_MODERATION means the content
// moderation pipeline caught the message / post before it was
// saved and asked admins to review — the offender never actually
// reached the other user.
export default function SourceBadge({ source }) {
  const isAuto = source === 'AUTO_MODERATION';
  const label = isAuto ? 'Auto-flag' : 'User report';
  const tone = isAuto ? 'source-auto' : 'source-user';
  return (
    <span
      className={`source-badge ${tone}`}
      title={
        isAuto
          ? 'Blocked by content moderation before being saved. The other user never received this content.'
          : 'A real user reported this content from the app.'
      }
    >
      {isAuto ? '⚙' : '✋'} {label}
    </span>
  );
}
