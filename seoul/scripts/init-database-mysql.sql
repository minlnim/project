-- Seoul Portal 초기 데이터 삽입 스크립트 (MySQL/Aurora)
-- 테스트 사용자 및 조직도 데이터

-- 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS corpportal;
USE corpportal;

-- 직원 테이블 (employees)
CREATE TABLE IF NOT EXISTS employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    department VARCHAR(100),
    position VARCHAR(100),
    phone VARCHAR(50),
    hire_date DATE DEFAULT (CURRENT_DATE),
    manager_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (manager_id) REFERENCES employees(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 부서 테이블 (departments)
CREATE TABLE IF NOT EXISTS departments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    manager_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (manager_id) REFERENCES employees(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 공지사항 테이블 (notices)
CREATE TABLE IF NOT EXISTS notices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    author_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    views INT DEFAULT 0,
    FOREIGN KEY (author_id) REFERENCES employees(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 결재 테이블 (approvals)
CREATE TABLE IF NOT EXISTS approvals (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    requester_id INT,
    approver_id INT,
    status VARCHAR(50) DEFAULT 'pending', -- pending, approved, rejected
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (requester_id) REFERENCES employees(id),
    FOREIGN KEY (approver_id) REFERENCES employees(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 테스트 직원 데이터 삽입
INSERT INTO employees (email, name, department, position, phone) VALUES
    ('ceo@company.com', '홍길동', '경영진', '대표이사', '010-1234-5678'),
    ('cto@company.com', '김철수', '기술본부', '기술이사', '010-2345-6789'),
    ('manager1@company.com', '이영희', '개발팀', '팀장', '010-3456-7890'),
    ('dev1@company.com', '박민수', '개발팀', '선임개발자', '010-4567-8901'),
    ('dev2@company.com', '최지혜', '개발팀', '주임개발자', '010-5678-9012'),
    ('hr@company.com', '정수현', '인사팀', '팀장', '010-6789-0123')
ON DUPLICATE KEY UPDATE email = email;

-- 조직 관계 설정 (manager_id 업데이트)
UPDATE employees SET manager_id = (SELECT id FROM (SELECT id FROM employees WHERE email = 'ceo@company.com') AS temp)
WHERE email IN ('cto@company.com', 'hr@company.com');

UPDATE employees SET manager_id = (SELECT id FROM (SELECT id FROM employees WHERE email = 'cto@company.com') AS temp)
WHERE email = 'manager1@company.com';

UPDATE employees SET manager_id = (SELECT id FROM (SELECT id FROM employees WHERE email = 'manager1@company.com') AS temp)
WHERE email IN ('dev1@company.com', 'dev2@company.com');

-- 부서 데이터 삽입
INSERT INTO departments (name, description, manager_id) VALUES
    ('경영진', '회사 경영 총괄', (SELECT id FROM (SELECT id FROM employees WHERE email = 'ceo@company.com') AS temp)),
    ('기술본부', '기술 개발 및 운영', (SELECT id FROM (SELECT id FROM employees WHERE email = 'cto@company.com') AS temp)),
    ('개발팀', '소프트웨어 개발', (SELECT id FROM (SELECT id FROM employees WHERE email = 'manager1@company.com') AS temp)),
    ('인사팀', '인사 관리 및 채용', (SELECT id FROM (SELECT id FROM employees WHERE email = 'hr@company.com') AS temp))
ON DUPLICATE KEY UPDATE name = name;

-- 샘플 공지사항
INSERT INTO notices (title, content, author_id) VALUES
    ('회사 포털 시스템 오픈', '새로운 사내 포털 시스템이 오픈되었습니다. 많은 이용 부탁드립니다.', 
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'ceo@company.com') AS temp)),
    ('개발팀 워크샵 안내', '다음 주 금요일에 개발팀 워크샵이 있습니다. 참석 부탁드립니다.',
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'manager1@company.com') AS temp)),
    ('인사 평가 일정 안내', '2025년 상반기 인사 평가 일정을 안내드립니다.',
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'hr@company.com') AS temp));

-- 샘플 결재 문서
INSERT INTO approvals (title, content, requester_id, approver_id, status) VALUES
    ('출장 신청서', '클라이언트 미팅을 위한 출장 신청합니다.', 
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'dev1@company.com') AS temp),
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'manager1@company.com') AS temp),
     'pending'),
    ('휴가 신청서', '다음 주 월요일 연차 휴가 신청합니다.',
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'dev2@company.com') AS temp),
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'manager1@company.com') AS temp),
     'approved'),
    ('예산 승인 요청', '개발 장비 구매를 위한 예산 승인 요청드립니다.',
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'manager1@company.com') AS temp),
     (SELECT id FROM (SELECT id FROM employees WHERE email = 'cto@company.com') AS temp),
     'pending');

-- 인덱스 생성
CREATE INDEX idx_employees_email ON employees(email);
CREATE INDEX idx_employees_department ON employees(department);
CREATE INDEX idx_employees_manager ON employees(manager_id);
CREATE INDEX idx_notices_author ON notices(author_id);
CREATE INDEX idx_approvals_requester ON approvals(requester_id);
CREATE INDEX idx_approvals_approver ON approvals(approver_id);
CREATE INDEX idx_approvals_status ON approvals(status);

-- 완료 메시지
SELECT 'Database initialization completed successfully!' AS status;
