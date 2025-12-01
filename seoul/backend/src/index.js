import express from "express";
import cors from "cors";
import morgan from "morgan";
import dotenv from "dotenv";
import { CognitoIdentityProviderClient, InitiateAuthCommand } from "@aws-sdk/client-cognito-identity-provider";
import jwt from "jsonwebtoken";
import mysql from "mysql2/promise";

dotenv.config();

const app = express();

const PORT = process.env.PORT || 8080;
const APP_VERSION = "1.0.1";
const AWS_REGION = process.env.AWS_REGION || "ap-northeast-2";
const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;
const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID;

if (!COGNITO_CLIENT_ID) {
  console.warn("WARNING: COGNITO_CLIENT_ID is not set. /auth/login will not work correctly until this is configured.");
}

const DB_POOL = mysql.createPool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  charset: 'utf8mb4',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

const cognito = new CognitoIdentityProviderClient({ region: AWS_REGION });

app.use(cors({
  origin: [
    'http://localhost:3000',
    'http://seoul-portal-seoul-frontend-env.eba-npadbvru.ap-northeast-2.elasticbeanstalk.com',
    'https://d28e0o760kyoll.cloudfront.net'
  ],
  credentials: true
}));
app.use(express.json());
app.use(morgan("combined"));

// UTF-8 응답 헤더 설정
app.use((req, res, next) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  next();
});

app.get("/health", async (req, res) => {
  try {
    await DB_POOL.query("SELECT 1");
    res.json({ status: "ok", db: "ok" });
  } catch (err) {
    console.error("DB health check failed:", err);
    res.status(500).json({ status: "error", db: "ng" });
  }
});

app.post("/auth/login", async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ message: "username, password 필수" });
  }

  try {
    const cmd = new InitiateAuthCommand({
      AuthFlow: "USER_PASSWORD_AUTH",
      ClientId: COGNITO_CLIENT_ID,
      AuthParameters: {
        USERNAME: username,
        PASSWORD: password,
      },
    });

    const out = await cognito.send(cmd);
    const authResult = out.AuthenticationResult;

    if (!authResult || !authResult.IdToken) {
      return res.status(401).json({ message: "로그인 실패 (토큰 없음)" });
    }

    const idToken = authResult.IdToken;
    const accessToken = authResult.AccessToken;
    const refreshToken = authResult.RefreshToken;

    const decoded = jwt.decode(idToken);
    const email = decoded?.email || decoded?.username || username;

    let employee = null;
    try {
      const [rows] = await DB_POOL.query(
        "SELECT id, email, name, department, position FROM employees WHERE email = ?",
        [email]
      );
      employee = rows[0] || null;
    } catch (err) {
      console.error("employees 조회 실패:", err);
    }

    return res.json({
      idToken,
      accessToken,
      refreshToken,
      employee,
    });
  } catch (err) {
    console.error("Cognito 로그인 실패:", err);
    return res.status(401).json({ message: "로그인 실패", error: err.message });
  }
});

app.use("/api", async (req, res, next) => {
  const auth = req.headers["authorization"] || "";
  const token = auth.replace("Bearer ", "");
  if (!token) {
    console.log("JWT 토큰 없음 - Authorization 헤더:", auth);
    return res.status(401).json({ message: "JWT 토큰 없음" });
  }
  const decoded = jwt.decode(token);
  if (!decoded) {
    console.log("JWT 디코드 실패 - 토큰:", token.substring(0, 20) + "...");
    return res.status(401).json({ message: "JWT 디코드 실패" });
  }
  req.user = decoded;
  next();
});

app.get("/api/me", async (req, res) => {
  const email = req.user?.email || req.user?.username;
  if (!email) {
    return res.status(400).json({ message: "토큰에 email/username claim 없음" });
  }
  try {
    const [rows] = await DB_POOL.query(
      "SELECT id, email, name, department, position FROM employees WHERE email = ?",
      [email]
    );
    if (!rows[0]) {
      return res.status(404).json({ message: "직원 정보 없음" });
    }
    res.json(rows[0]);
  } catch (err) {
    console.error("/api/me 조회 실패:", err);
    res.status(500).json({ message: "서버 오류" });
  }
});

app.get("/api/notices", async (req, res) => {
  try {
    const [rows] = await DB_POOL.query(
      "SELECT id, title, content, created_at FROM notices ORDER BY created_at DESC LIMIT 50"
    );
    res.json(rows);
  } catch (err) {
    console.error("/api/notices 조회 실패:", err);
    res.status(500).json({ message: "서버 오류" });
  }
});

app.get("/api/org", async (req, res) => {
  try {
    // 모든 직원 정보 조회 (조직도 구성)
    const [rows] = await DB_POOL.query(`
      SELECT 
        id, 
        email, 
        name, 
        department, 
        position, 
        phone,
        manager_id,
        hire_date
      FROM employees 
      ORDER BY 
        CASE position
          WHEN '대표이사' THEN 1
          WHEN '기술이사' THEN 2
          WHEN '팀장' THEN 3
          WHEN '선임개발자' THEN 4
          WHEN '주임개발자' THEN 5
          ELSE 6
        END,
        department,
        name
    `);

    // 부서별로 그룹화
    const departments = {};
    rows.forEach(emp => {
      const dept = emp.department || '미분류';
      if (!departments[dept]) {
        departments[dept] = [];
      }
      departments[dept].push({
        id: emp.id,
        email: emp.email,
        name: emp.name,
        position: emp.position,
        phone: emp.phone,
        manager_id: emp.manager_id,
        hire_date: emp.hire_date
      });
    });

    // 조직도 트리 구조로 변환
    const buildTree = (employees) => {
      const empMap = new Map();
      const roots = [];

      employees.forEach(emp => empMap.set(emp.id, { ...emp, children: [] }));

      employees.forEach(emp => {
        const node = empMap.get(emp.id);
        if (emp.manager_id && empMap.has(emp.manager_id)) {
          empMap.get(emp.manager_id).children.push(node);
        } else {
          roots.push(node);
        }
      });

      return roots;
    };

    res.json({
      departments,
      employees: rows,
      tree: buildTree(rows)
    });
  } catch (err) {
    console.error("/api/org 조회 실패:", err);
    res.status(500).json({ message: "서버 오류", error: err.message });
  }
});

app.get("/api/employees", async (req, res) => {
  try {
    const [rows] = await DB_POOL.query(`
      SELECT 
        e.id,
        e.email,
        e.name,
        e.department,
        e.position,
        e.phone,
        e.hire_date,
        e.manager_id,
        m.name as manager_name
      FROM employees e
      LEFT JOIN employees m ON e.manager_id = m.id
      ORDER BY e.department, e.position, e.name
    `);
    res.json(rows);
  } catch (err) {
    console.error("/api/employees 조회 실패:", err);
    res.status(500).json({ message: "서버 오류" });
  }
});

app.get("/api/approvals", async (req, res) => {
  try {
    const [rows] = await DB_POOL.query(`
      SELECT 
        a.id,
        a.title,
        a.content,
        a.status,
        a.created_at,
        a.updated_at,
        r.name as requester_name,
        r.department as requester_department,
        ap.name as approver_name
      FROM approvals a
      LEFT JOIN employees r ON a.requester_id = r.id
      LEFT JOIN employees ap ON a.approver_id = ap.id
      ORDER BY a.created_at DESC
      LIMIT 50
    `);
    res.json(rows);
  } catch (err) {
    console.error("/api/approvals 조회 실패:", err);
    res.status(500).json({ message: "서버 오류" });
  }
});

app.use((req, res) => {
  res.status(404).json({ message: "Not Found" });
});

app.listen(PORT, () => {
  console.log(`Backend API listening on port ${PORT}`);
});
