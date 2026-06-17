import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './styles.css';

class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null, info: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    // Surface the error to the page so the developer can read it
    // without opening the devtools console.
    this.setState({ info });
    // eslint-disable-next-line no-console
    console.error('[ErrorBoundary]', error, info);
  }

  render() {
    if (this.state.error) {
      const stack = this.state.error.stack || String(this.state.error);
      return (
        <div
          style={{
            padding: '24px',
            fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
            color: '#9b1c42',
            background: '#ffe8ef',
            border: '1px solid #ffb6c8',
            margin: '24px',
            borderRadius: '12px',
            whiteSpace: 'pre-wrap',
            wordBreak: 'break-word',
          }}
        >
          <h1 style={{ margin: '0 0 12px' }}>Admin failed to render</h1>
          <strong>{this.state.error.message || String(this.state.error)}</strong>
          <pre style={{ marginTop: '12px', fontSize: '12px' }}>{stack}</pre>
        </div>
      );
    }
    return this.props.children;
  }
}

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>,
);
