--Library Management System Database Schema

-- Create the database(droping a similar existing database if any) 
DROP DATABASE IF EXISTS library_management;
CREATE DATABASE library_management;
USE library_management;

-- Members Table: Stores library member information
CREATE TABLE members (
    member_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    membership_date DATE NOT NULL,
    membership_status ENUM('active', 'expired', 'suspended') DEFAULT 'active',
    CONSTRAINT chk_email CHECK (email LIKE '%@%.%')
) COMMENT 'Stores library member information';

-- Authors Table: Stores author information
CREATE TABLE authors (
    author_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    birth_year SMALLINT,
    nationality VARCHAR(50),
    biography TEXT
) COMMENT 'Stores author information';

-- Publishers Table: Stores publisher information
CREATE TABLE publishers (
    publisher_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address TEXT,
    contact_email VARCHAR(100),
    website VARCHAR(255)
) COMMENT 'Stores publisher information';

-- Books Table: Stores book information
CREATE TABLE books (
    book_id INT AUTO_INCREMENT PRIMARY KEY,
    isbn VARCHAR(20) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    publisher_id INT NOT NULL,
    publication_year SMALLINT,
    edition VARCHAR(20),
    category VARCHAR(50),
    language VARCHAR(30) DEFAULT 'English',
    page_count INT,
    description TEXT,
    CONSTRAINT fk_book_publisher FOREIGN KEY (publisher_id)
        REFERENCES publishers(publisher_id)
        ON DELETE RESTRICT
) COMMENT 'Stores book information';

-- Book_Authors Table: Junction table for many-to-many relationship between books and authors
CREATE TABLE book_authors (
    book_id INT NOT NULL,
    author_id INT NOT NULL,
    PRIMARY KEY (book_id, author_id),
    CONSTRAINT fk_ba_book FOREIGN KEY (book_id)
        REFERENCES books(book_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_ba_author FOREIGN KEY (author_id)
        REFERENCES authors(author_id)
        ON DELETE CASCADE
) COMMENT 'Junction table for book-author relationships';

-- Book_Copies Table: Stores individual copies of books
CREATE TABLE book_copies (
    copy_id INT AUTO_INCREMENT PRIMARY KEY,
    book_id INT NOT NULL,
    barcode VARCHAR(50) UNIQUE NOT NULL,
    acquisition_date DATE NOT NULL,
    status ENUM('available', 'checked_out', 'lost', 'damaged', 'in_repair') DEFAULT 'available',
    location VARCHAR(50),
    notes TEXT,
    CONSTRAINT fk_copy_book FOREIGN KEY (book_id)
        REFERENCES books(book_id)
        ON DELETE CASCADE
) COMMENT 'Stores individual copies of books';

-- Loans Table: Tracks book loans to members
CREATE TABLE loans (
    loan_id INT AUTO_INCREMENT PRIMARY KEY,
    copy_id INT NOT NULL,
    member_id INT NOT NULL,
    loan_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date DATE NOT NULL,
    return_date DATETIME,
    status ENUM('active', 'returned', 'overdue', 'lost') DEFAULT 'active',
    CONSTRAINT fk_loan_copy FOREIGN KEY (copy_id)
        REFERENCES book_copies(copy_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_loan_member FOREIGN KEY (member_id)
        REFERENCES members(member_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_due_date CHECK (due_date > DATE(loan_date))
) COMMENT 'Tracks book loans to members';

-- Fines Table: Tracks fines associated with overdue/lost books
CREATE TABLE fines (
    fine_id INT AUTO_INCREMENT PRIMARY KEY,
    loan_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    issue_date DATE NOT NULL,
    payment_date DATE,
    status ENUM('pending', 'paid', 'waived') DEFAULT 'pending',
    notes TEXT,
    CONSTRAINT fk_fine_loan FOREIGN KEY (loan_id)
        REFERENCES loans(loan_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_amount CHECK (amount >= 0)
) COMMENT 'Tracks fines for overdue/lost books';

-- Reservations Table: Tracks book reservations
CREATE TABLE reservations (
    reservation_id INT AUTO_INCREMENT PRIMARY KEY,
    book_id INT NOT NULL,
    member_id INT NOT NULL,
    reservation_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATETIME NOT NULL,
    status ENUM('pending', 'fulfilled', 'cancelled', 'expired') DEFAULT 'pending',
    CONSTRAINT fk_reservation_book FOREIGN KEY (book_id)
        REFERENCES books(book_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_reservation_member FOREIGN KEY (member_id)
        REFERENCES members(member_id)
        ON DELETE CASCADE
) COMMENT 'Tracks book reservations';

-- Staff Table: Library staff information
CREATE TABLE staff (
    staff_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    position VARCHAR(50) NOT NULL,
    hire_date DATE NOT NULL,
    salary DECIMAL(10,2),
    CONSTRAINT chk_staff_email CHECK (email LIKE '%@%.%'),
    CONSTRAINT chk_salary CHECK (salary >= 0)
) COMMENT 'Stores library staff information';

-- Create indexes for performance optimization
CREATE INDEX idx_books_title ON books(title);
CREATE INDEX idx_members_name ON members(last_name, first_name);
CREATE INDEX idx_loans_member ON loans(member_id);
CREATE INDEX idx_loans_status ON loans(status);
CREATE INDEX idx_book_copies_status ON book_copies(status);
CREATE INDEX idx_fines_status ON fines(status);

-- Create a view for currently available books
CREATE VIEW available_books AS
SELECT b.book_id, b.title, b.isbn, a.name AS author, COUNT(bc.copy_id) AS available_copies
FROM books b
JOIN book_authors ba ON b.book_id = ba.book_id
JOIN authors a ON ba.author_id = a.author_id
JOIN book_copies bc ON b.book_id = bc.book_id
WHERE bc.status = 'available'
GROUP BY b.book_id, b.title, b.isbn, a.name;

-- Create a view for overdue loans
CREATE VIEW overdue_loans AS
SELECT l.loan_id, m.first_name, m.last_name, b.title, bc.barcode, 
       l.loan_date, l.due_date, DATEDIFF(CURRENT_DATE, l.due_date) AS days_overdue
FROM loans l
JOIN members m ON l.member_id = m.member_id
JOIN book_copies bc ON l.copy_id = bc.copy_id
JOIN books b ON bc.book_id = b.book_id
WHERE l.status = 'active' AND l.return_date IS NULL AND l.due_date < CURRENT_DATE;

-- Create a stored procedure for checking out a book
DELIMITER //
CREATE PROCEDURE checkout_book(
    IN p_copy_id INT,
    IN p_member_id INT,
    IN p_due_days INT
)
BEGIN
    DECLARE copy_status VARCHAR(20);
    DECLARE member_status VARCHAR(20);
    
    -- Check copy status
    SELECT status INTO copy_status FROM book_copies WHERE copy_id = p_copy_id;
    
    -- Check member status
    SELECT membership_status INTO member_status FROM members WHERE member_id = p_member_id;
    
    -- Validate checkout conditions
    IF copy_status != 'available' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Book copy is not available for checkout';
    ELSEIF member_status != 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member account is not active';
    ELSE
        -- Create loan record
        INSERT INTO loans (copy_id, member_id, due_date)
        VALUES (p_copy_id, p_member_id, DATE_ADD(CURRENT_DATE, INTERVAL p_due_days DAY));
        
        -- Update copy status
        UPDATE book_copies SET status = 'checked_out' WHERE copy_id = p_copy_id;
    END IF;
END //
DELIMITER ;

-- Create a trigger to update loan status when return_date is set
DELIMITER //
CREATE TRIGGER update_loan_status
BEFORE UPDATE ON loans
FOR EACH ROW
BEGIN
    IF NEW.return_date IS NOT NULL AND OLD.return_date IS NULL THEN
        SET NEW.status = 'returned';
        
        -- Update book copy status
        UPDATE book_copies SET status = 'available' WHERE copy_id = NEW.copy_id;
    END IF;
END //
DELIMITER ;
