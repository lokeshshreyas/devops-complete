import os
import time
import logging
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
import jwt
from datetime import datetime, timedelta

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get(
    'DATABASE_URL',
    'postgresql://thermos:thermos@postgres:5432/thermos'
)
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-prod')

db = SQLAlchemy(app)
CORS(app)

# Retry DB connection on startup
max_retries = 30
for i in range(max_retries):
    try:
        with app.app_context():
            db.engine.connect()
        logger.info("Database connected successfully.")
        break
    except Exception as e:
        logger.warning(f"DB connection attempt {i+1}/{max_retries} failed: {e}")
        time.sleep(2)
else:
    logger.error("Could not connect to database after max retries.")

# Models
class User(db.Model):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    bookmarks = db.relationship('Bookmark', backref='user', lazy=True, cascade='all, delete-orphan')

class Bookmark(db.Model):
    __tablename__ = 'bookmarks'
    id = db.Column(db.Integer, primary_key=True)
    url = db.Column(db.String(512), nullable=False)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=True)
    tags = db.Column(db.String(200), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)

with app.app_context():
    db.create_all()

# Health check
@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "service": "thermos-backend"}), 200

# Auth helpers
def token_required(f):
    def decorator(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({"message": "Token is missing"}), 401
        try:
            token = token.replace("Bearer ", "")
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
            current_user = User.query.get(data['user_id'])
            if not current_user:
                return jsonify({"message": "User not found"}), 401
        except jwt.ExpiredSignatureError:
            return jsonify({"message": "Token expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"message": "Token is invalid"}), 401
        return f(current_user, *args, **kwargs)
    decorator.__name__ = f.__name__
    return decorator

# Routes
@app.route('/api/register', methods=['POST'])
def register():
    data = request.get_json()
    if not data or not data.get('username') or not data.get('password') or not data.get('email'):
        return jsonify({"message": "Missing required fields"}), 400
    if User.query.filter_by(username=data['username']).first():
        return jsonify({"message": "Username already exists"}), 409
    if User.query.filter_by(email=data['email']).first():
        return jsonify({"message": "Email already exists"}), 409

    hashed = generate_password_hash(data['password'])
    new_user = User(username=data['username'], email=data['email'], password_hash=hashed)
    db.session.add(new_user)
    db.session.commit()
    return jsonify({"message": "User created successfully", "user_id": new_user.id}), 201

@app.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data or not data.get('username') or not data.get('password'):
        return jsonify({"message": "Missing credentials"}), 400
    user = User.query.filter_by(username=data['username']).first()
    if not user or not check_password_hash(user.password_hash, data['password']):
        return jsonify({"message": "Invalid credentials"}), 401
    token = jwt.encode(
        {"user_id": user.id, "exp": datetime.utcnow() + timedelta(hours=24)},
        app.config['SECRET_KEY'],
        algorithm="HS256"
    )
    return jsonify({"token": token, "username": user.username, "user_id": user.id}), 200

@app.route('/api/bookmarks', methods=['GET'])
@token_required
def get_bookmarks(current_user):
    bookmarks = Bookmark.query.filter_by(user_id=current_user.id).order_by(Bookmark.created_at.desc()).all()
    return jsonify([{
        "id": b.id,
        "url": b.url,
        "title": b.title,
        "description": b.description,
        "tags": b.tags,
        "created_at": b.created_at.isoformat()
    } for b in bookmarks]), 200

@app.route('/api/bookmarks', methods=['POST'])
@token_required
def create_bookmark(current_user):
    data = request.get_json()
    if not data or not data.get('url') or not data.get('title'):
        return jsonify({"message": "URL and title are required"}), 400
    bookmark = Bookmark(
        url=data['url'],
        title=data['title'],
        description=data.get('description', ''),
        tags=data.get('tags', ''),
        user_id=current_user.id
    )
    db.session.add(bookmark)
    db.session.commit()
    return jsonify({"message": "Bookmark created", "id": bookmark.id}), 201

@app.route('/api/bookmarks/<int:bookmark_id>', methods=['PUT'])
@token_required
def update_bookmark(current_user, bookmark_id):
    bookmark = Bookmark.query.filter_by(id=bookmark_id, user_id=current_user.id).first()
    if not bookmark:
        return jsonify({"message": "Bookmark not found"}), 404
    data = request.get_json()
    bookmark.url = data.get('url', bookmark.url)
    bookmark.title = data.get('title', bookmark.title)
    bookmark.description = data.get('description', bookmark.description)
    bookmark.tags = data.get('tags', bookmark.tags)
    db.session.commit()
    return jsonify({"message": "Bookmark updated"}), 200

@app.route('/api/bookmarks/<int:bookmark_id>', methods=['DELETE'])
@token_required
def delete_bookmark(current_user, bookmark_id):
    bookmark = Bookmark.query.filter_by(id=bookmark_id, user_id=current_user.id).first()
    if not bookmark:
        return jsonify({"message": "Bookmark not found"}), 404
    db.session.delete(bookmark)
    db.session.commit()
    return jsonify({"message": "Bookmark deleted"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
