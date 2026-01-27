-- Database: ezmtls
CREATE DATABASE IF NOT EXISTS `ezmtls` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `ezmtls`;

-- Table: audit_logs
CREATE TABLE IF NOT EXISTS `audit_logs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `logged_at` datetime DEFAULT NULL,
  `idp` varchar(20) DEFAULT NULL,
  `user_name` varchar(100) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `common_name` varchar(255) NOT NULL,
  `action` varchar(50) DEFAULT NULL,
  `detail` varchar(255) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Table: certificates
CREATE TABLE IF NOT EXISTS `certificates` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `idp` varchar(20) DEFAULT NULL,
  `user_name` varchar(100) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `common_name` varchar(255) NOT NULL,
  `serial` varchar(128) NOT NULL,
  `fingerprint_sha1` varchar(64) DEFAULT NULL,
  `fingerprint_sha256` varchar(96) DEFAULT NULL,
  `issued_at` datetime DEFAULT NULL,
  `expires_at` datetime NOT NULL,
  `status` enum('valid','revoked','expired') DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
