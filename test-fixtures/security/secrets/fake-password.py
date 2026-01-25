# TEST FILE: Contains fake credentials for workflow validation
# These are NOT real credentials - they are test patterns

# Hardcoded database password (fake)
DB_PASSWORD = "MySecretPassword123!"

# Connection string with credentials (fake)
DATABASE_URL = "postgres://admin:supersecret123@localhost:5432/mydb"

# MongoDB connection (fake)
MONGO_URI = "mongodb://root:password123@localhost:27017/admin"

# Private key pattern (fake - not a real key)
PRIVATE_KEY = """-----BEGIN RSA PRIVATE KEY-----
MIIBogIBAAJBALRiMLAHudeSA2FAKE_KEY_PATTERN_NOT_REAL
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-----END RSA PRIVATE KEY-----"""


def connect_database():
    """Connect using hardcoded credentials (insecure pattern)."""
    password = "another_hardcoded_secret"
    return f"Connected with {password}"


class Config:
    # Hardcoded secrets in class (bad practice)
    secret_key = "jwt_secret_key_abc123xyz789"
    api_token = "bearer_token_1234567890abcdef"
