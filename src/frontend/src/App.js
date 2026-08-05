import React, { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import Login from './components/Login';
import Register from './components/Register';
import Dashboard from './components/Dashboard';

const API_BASE = process.env.REACT_APP_API_URL || '/api';

function App() {
    const [user, setUser] = useState(null);

    useEffect(() => {
        const stored = localStorage.getItem('thermos_user');
        if (stored) setUser(JSON.parse(stored));
    }, []);

    return (
        <Router>
            <div style={{ minHeight: '100vh' }}>
                <Routes>
                    <Route path="/login" element={user ? <Navigate to="/" /> : <Login setUser={setUser} apiBase={API_BASE} />} />
                    <Route path="/register" element={user ? <Navigate to="/" /> : <Register apiBase={API_BASE} />} />
                    <Route path="/" element={user ? <Dashboard user={user} setUser={setUser} apiBase={API_BASE} /> : <Navigate to="/login" />} />
                </Routes>
            </div>
        </Router>
    );
}

export default App;
