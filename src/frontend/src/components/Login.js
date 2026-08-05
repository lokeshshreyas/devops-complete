import React, { useState } from 'react';
import axios from 'axios';

function Login({ setUser, apiBase }) {
    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [error, setError] = useState('');

    const handleSubmit = async (e) => {
        e.preventDefault();
        try {
            const res = await axios.post(`${apiBase}/login`, { username, password });
            const userData = { token: res.data.token, username: res.data.username };
            localStorage.setItem('thermos_user', JSON.stringify(userData));
            setUser(userData);
        } catch (err) {
            setError(err.response?.data?.message || 'Login failed');
        }
    };

    return (
        <div style={styles.container}>
            <div style={styles.card}>
                <h2 style={styles.title}>Thermos Bookmark Manager</h2>
                <form onSubmit={handleSubmit}>
                    <input style={styles.input} type="text" placeholder="Username" value={username} onChange={e => setUsername(e.target.value)} required />
                    <input style={styles.input} type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} required />
                    {error && <p style={styles.error}>{error}</p>}
                    <button style={styles.button} type="submit">Login</button>
                </form>
                <p style={styles.link}>Don't have an account? <a href="/register">Register</a></p>
            </div>
        </div>
    );
}

const styles = {
    container: { display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)' },
    card: { background: 'white', padding: '40px', borderRadius: '12px', boxShadow: '0 10px 40px rgba(0,0,0,0.1)', width: '360px' },
    title: { textAlign: 'center', marginBottom: '24px', color: '#333' },
    input: { width: '100%', padding: '12px', marginBottom: '16px', border: '1px solid #ddd', borderRadius: '6px', fontSize: '14px', boxSizing: 'border-box' },
    button: { width: '100%', padding: '12px', background: '#667eea', color: 'white', border: 'none', borderRadius: '6px', fontSize: '16px', cursor: 'pointer' },
    error: { color: '#e74c3c', fontSize: '13px', marginBottom: '12px' },
    link: { textAlign: 'center', marginTop: '16px', fontSize: '13px', color: '#666' }
};

export default Login;
