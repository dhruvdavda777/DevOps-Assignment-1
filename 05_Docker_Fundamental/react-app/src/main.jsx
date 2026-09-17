import React from 'react';
import { createRoot } from 'react-dom/client';

function App() {
  return (
    <div style={{ fontFamily: 'system-ui, sans-serif', textAlign: 'center', paddingTop: 80 }}>
      <h1>Hello World from React</h1>
      <p>Dhruv Davda &middot; 24BCS10203 &middot; Group A</p>
      <p>Built with Vite, served as static files by nginx</p>
    </div>
  );
}

createRoot(document.getElementById('root')).render(<App />);
