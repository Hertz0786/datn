import { useEffect, useState } from 'react';
import PageHeader from '../components/PageHeader';
import { api } from '../services/api';

const defaultRules = [
  'No bullying, threats or insulting language.',
  'Do not share phone numbers, home address or school details.',
  'Keep posts safe for ages 7 to 14.',
  'Stop interaction when someone asks for space.',
];

export default function SafetyPage() {
  const [rules, setRules] = useState(defaultRules);
  const [newRule, setNewRule] = useState('');
  const [safeSearch, setSafeSearch] = useState(true);
  const [autoHide, setAutoHide] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    api
      .getSafety()
      .then((payload) => {
        const data = payload.data || {};
        setRules(data.rules || defaultRules);
        setSafeSearch(data.safeSearchDefault !== false);
        setAutoHide(data.autoHideHighRisk !== false);
      })
      .catch(() => {});
  }, []);

  async function saveConfig(next = {}) {
    const body = {
      safeSearchDefault: next.safeSearchDefault ?? safeSearch,
      autoHideHighRisk: next.autoHideHighRisk ?? autoHide,
      rules: next.rules ?? rules,
    };
    setSaving(true);
    try {
      await api.updateSafety(body);
    } catch {
      // Keep local state responsive even if backend is temporarily unavailable.
    } finally {
      setSaving(false);
    }
  }

  function addRule(event) {
    event.preventDefault();
    if (!newRule.trim()) return;
    const nextRules = [...rules, newRule.trim()];
    setRules(nextRules);
    setNewRule('');
    saveConfig({ rules: nextRules });
  }

  return (
    <section className="page">
      <PageHeader
        title="Safety configuration"
        description="Control safety defaults, community rules and automated moderation settings."
      />
      <div className="split-grid">
        <div className="panel form-panel">
          <h2>Automation</h2>
          <label className="switch-row">
            <input
              type="checkbox"
              checked={safeSearch}
              onChange={(event) => {
                setSafeSearch(event.target.checked);
                saveConfig({ safeSearchDefault: event.target.checked });
              }}
            />
            Force safe search by default
          </label>
          <label className="switch-row">
            <input
              type="checkbox"
              checked={autoHide}
              onChange={(event) => {
                setAutoHide(event.target.checked);
                saveConfig({ autoHideHighRisk: event.target.checked });
              }}
            />
            Auto-hide high-risk flagged content
          </label>
          {saving && <p>Saving...</p>}
        </div>
        <form className="panel form-panel" onSubmit={addRule}>
          <h2>Community rules</h2>
          <div className="stack">
            {rules.map((rule) => <p className="rule-line" key={rule}>{rule}</p>)}
          </div>
          <input placeholder="Add new rule..." value={newRule} onChange={(event) => setNewRule(event.target.value)} />
          <button className="primary-button">Add rule</button>
        </form>
      </div>
    </section>
  );
}
