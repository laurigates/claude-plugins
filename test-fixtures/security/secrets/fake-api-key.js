// TEST FILE: Contains patterns for secrets detection validation
// These patterns should trigger our workflow but NOT GitHub's secret scanning

// Pattern resembling AWS access key (intentionally invalid format)
const awsStyleKey = "TESTAKIA_NOT_REAL_12345678";
const awsStyleSecret = "test/wJalrXUtnFEMI/notreal/example";

// Pattern resembling payment key (using test prefix)
const paymentKey = "sk_test_FakeKey123456NotReal789";

// Pattern that looks like a token (intentionally corrupted)
const tokenPattern = "token_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123";

// Generic API key assignment (should be detected)
const apiKey = "my_super_secret_api_key_12345678901234567890";

// Hardcoded password pattern (should be detected)
const password = "P@ssw0rd123!Secret";
const dbPassword = "database_password_abc123";

// Connection string pattern (should be detected)
const mongoUrl = "mongodb://user:secretpass123@localhost:27017/db";

export function getConfig() {
  return {
    aws: { accessKey: awsStyleKey, secretKey: awsStyleSecret },
    payment: paymentKey,
    token: tokenPattern,
    api: apiKey,
    db: { password: dbPassword, url: mongoUrl },
  };
}
