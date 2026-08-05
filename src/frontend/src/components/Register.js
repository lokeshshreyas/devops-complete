import React, { useState } from 'react';
import axios from 'axios';

function Register({ apiBase }) {
    const [form, setForm] = useState({ username: '', email: '', password: '' });
    const [error, setError] = useState('');
    const [success, setSuccess] = useState('');

    const handleChange = (e) => setForm({ ...form, [e.target.name]: e.target.value });

    const handleSubmit = async (e) => {
        e.preventDefault();
        try {
            await axios.post(`${apiBase}/register`, form);
            setSuccess('Account created! Redirecting to login...');
            setTimeout(() => window.location.href = '/login', 1500);
        } catch (err) {
            setError(err.response?.data?.message || 'Registration failed');
        }
    };

    return (
        <div style={styles.container}>
            <div style={styles.card}>
                <h2 style={styles.title}>Create Account</h2>
                <form onSubmit={handleSubmit}>
                    <input style={styles.input} name="username" placeholder="Username" value={form.username} onChange={handleChange} required />
                    <input style={styles.input} name="email" type="email" placeholder="Email" value={form.email} onChange={handleChange} required />
                    <input style={styles.input} name="password" type="password" placeholder="Password" value={form.password} onChange={handleChange} required />
                    {error && <p style={styles.error}>{error}</p>}
                    {success && <p style={styles.success}>{success}</p>}
                    <button style={styles.button} type="submit">Register</button>
                </form>
                <p style={styles.link}>Already have an account? <a href="/login">Login</a></p>
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
    success: { color: '#27ae60', fontSize: '13px', marginBottom: '12px' },
    link: { textAlign: 'center', marginTop: '16px', fontSize: '13px', color: '#666' }
};

export default Register;
