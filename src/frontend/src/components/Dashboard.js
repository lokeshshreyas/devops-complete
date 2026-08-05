import React, { useState, useEffect } from 'react';
import axios from 'axios';

function Dashboard({ user, setUser, apiBase }) {
    const [bookmarks, setBookmarks] = useState([]);
    const [form, setForm] = useState({ url: '', title: '', description: '', tags: '' });
    const [editing, setEditing] = useState(null);
    const [error, setError] = useState('');

    const headers = { Authorization: `Bearer ${user.token}` };

    const fetchBookmarks = async () => {
        try {
            const res = await axios.get(`${apiBase}/bookmarks`, { headers });
            setBookmarks(res.data);
        } catch (err) {
            if (err.response?.status === 401) {
                localStorage.removeItem('thermos_user');
                setUser(null);
            }
        }
    };

    useEffect(() => { fetchBookmarks(); }, []);

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');
        try {
            if (editing) {
                await axios.put(`${apiBase}/bookmarks/${editing}`, form, { headers });
                setEditing(null);
            } else {
                await axios.post(`${apiBase}/bookmarks`, form, { headers });
            }
            setForm({ url: '', title: '', description: '', tags: '' });
            fetchBookmarks();
        } catch (err) {
            setError(err.response?.data?.message || 'Operation failed');
        }
    };

    const handleDelete = async (id) => {
        if (!window.confirm('Delete this bookmark?')) return;
        try {
            await axios.delete(`${apiBase}/bookmarks/${id}`, { headers });
            fetchBookmarks();
        } catch (err) {
            setError('Delete failed');
        }
    };

    const handleEdit = (b) => {
        setForm({ url: b.url, title: b.title, description: b.description || '', tags: b.tags || '' });
        setEditing(b.id);
    };

    const logout = () => {
        localStorage.removeItem('thermos_user');
        setUser(null);
    };

    return (
        <div style={styles.container}>
            <header style={styles.header}>
                <h1 style={styles.logo}>Thermos</h1>
                <div>
                    <span style={styles.user}>Welcome, {user.username}</span>
                    <button style={styles.logoutBtn} onClick={logout}>Logout</button>
                </div>
            </header>
            <main style={styles.main}>
                <div style={styles.formCard}>
                    <h3>{editing ? 'Edit Bookmark' : 'Add Bookmark'}</h3>
                    <form onSubmit={handleSubmit} style={styles.form}>
                        <input style={styles.input} placeholder="URL" value={form.url} onChange={e => setForm({...form, url: e.target.value})} required />
                        <input style={styles.input} placeholder="Title" value={form.title} onChange={e => setForm({...form, title: e.target.value})} required />
                        <input style={styles.input} placeholder="Description" value={form.description} onChange={e => setForm({...form, description: e.target.value})} />
                        <input style={styles.input} placeholder="Tags (comma separated)" value={form.tags} onChange={e => setForm({...form, tags: e.target.value})} />
                        {error && <p style={{color: '#e74c3c', fontSize: '13px'}}>{error}</p>}
                        <button style={styles.submitBtn} type="submit">{editing ? 'Update' : 'Add'}</button>
                        {editing && <button style={styles.cancelBtn} type="button" onClick={() => {setEditing(null); setForm({url:'',title:'',description:'',tags:''});}}>Cancel</button>}
                    </form>
                </div>
                <div style={styles.list}>
                    {bookmarks.length === 0 ? <p style={styles.empty}>No bookmarks yet. Add your first one above!</p> :
                        bookmarks.map(b => (
                            <div key={b.id} style={styles.card}>
                                <h4 style={styles.cardTitle}><a href={b.url} target="_blank" rel="noopener noreferrer" style={{color:'#667eea', textDecoration:'none'}}>{b.title}</a></h4>
                                <p style={styles.cardDesc}>{b.description}</p>
                                {b.tags && <span style={styles.tag}>{b.tags}</span>}
                                <div style={styles.actions}>
                                    <button style={styles.editBtn} onClick={() => handleEdit(b)}>Edit</button>
                                    <button style={styles.delBtn} onClick={() => handleDelete(b.id)}>Delete</button>
                                </div>
                            </div>
                        ))
                    }
                </div>
            </main>
        </div>
    );
}

const styles = {
    container: { minHeight: '100vh', background: '#f5f7fa' },
    header: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 32px', background: 'white', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' },
    logo: { margin: 0, color: '#667eea', fontSize: '24px' },
    user: { marginRight: '16px', color: '#666', fontSize: '14px' },
    logoutBtn: { padding: '8px 16px', background: '#e74c3c', color: 'white', border: 'none', borderRadius: '6px', cursor: 'pointer' },
    main: { maxWidth: '900px', margin: '0 auto', padding: '32px 16px' },
    formCard: { background: 'white', padding: '24px', borderRadius: '12px', marginBottom: '24px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' },
    form: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' },
    input: { padding: '10px', border: '1px solid #ddd', borderRadius: '6px', fontSize: '14px' },
    submitBtn: { gridColumn: 'span 2', padding: '12px', background: '#667eea', color: 'white', border: 'none', borderRadius: '6px', fontSize: '16px', cursor: 'pointer' },
    cancelBtn: { gridColumn: 'span 2', padding: '12px', background: '#95a5a6', color: 'white', border: 'none', borderRadius: '6px', fontSize: '16px', cursor: 'pointer', marginTop: '8px' },
    list: { display: 'grid', gap: '16px' },
    card: { background: 'white', padding: '20px', borderRadius: '12px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' },
    cardTitle: { margin: '0 0 8px 0', fontSize: '16px' },
    cardDesc: { margin: '0 0 8px 0', color: '#666', fontSize: '13px' },
    tag: { display: 'inline-block', background: '#e8f7f0', color: '#16a085', padding: '4px 10px', borderRadius: '20px', fontSize: '12px', marginBottom: '8px' },
    actions: { display: 'flex', gap: '8px', marginTop: '8px' },
    editBtn: { padding: '6px 12px', background: '#16a085', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' },
    delBtn: { padding: '6px 12px', background: '#e74c3c', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' },
    empty: { textAlign: 'center', color: '#999', padding: '40px' }
};

export default Dashboard;
