-- MySQL dump 10.13  Distrib 26.7.0, for macos27.0 (arm64)
--
-- Host: VDC.local    Database: levoci
-- ------------------------------------------------------
-- Server version	11.8.6-MariaDB-0+deb13u1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `classes`
--

DROP TABLE IF EXISTS `classes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `classes` (
  `id` uuid NOT NULL DEFAULT uuid(),
  `class` varchar(10) NOT NULL,
  `beginDate` date NOT NULL,
  `endDate` date NOT NULL,
  `classYear` int(11) NOT NULL,
  `studyFieldId` uuid NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `class` (`class`,`classYear`),
  KEY `studyFieldId` (`studyFieldId`),
  CONSTRAINT `classes_ibfk_1` FOREIGN KEY (`studyFieldId`) REFERENCES `studyFields` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `credentials`
--

DROP TABLE IF EXISTS `credentials`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `credentials` (
  `id` uuid NOT NULL DEFAULT uuid(),
  `email` varchar(128) NOT NULL,
  `password` char(60) NOT NULL,
  `tokenVersion` uuid NOT NULL DEFAULT uuid(),
  `isEmailVerified` tinyint(1) NOT NULL DEFAULT 0,
  `verificationEmailSentAt` timestamp NULL DEFAULT NULL,
  `dateOfCreation` timestamp NOT NULL DEFAULT current_timestamp(),
  `lastUpdated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  CONSTRAINT `chk_credentials_verified_sent_at` CHECK (`isEmailVerified` = 0 or `verificationEmailSentAt` is null)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `posts`
--

DROP TABLE IF EXISTS `posts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `posts` (
  `id` uuid NOT NULL DEFAULT uuid(),
  `title` varchar(200) NOT NULL,
  `content` varchar(1000) NOT NULL,
  `userId` uuid DEFAULT NULL,
  `isAnonymous` tinyint(1) NOT NULL DEFAULT 0,
  `timetableId` uuid DEFAULT NULL,
  `timetableDate` date DEFAULT NULL,
  `subjectId` smallint(5) unsigned DEFAULT NULL,
  `isLab` tinyint(1) DEFAULT NULL,
  `professorId` uuid DEFAULT NULL,
  `updatedAt` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `deletedAt` timestamp NULL DEFAULT NULL,
  `dateOfCreation` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `timetableId` (`timetableId`),
  KEY `subjectId` (`subjectId`,`isLab`),
  KEY `professorId` (`professorId`),
  KEY `idx_posts_dateOfCreation` (`dateOfCreation`),
  KEY `idx_posts_updatedAt` (`updatedAt`),
  KEY `idx_posts_deletedAt` (`deletedAt`,`dateOfCreation` DESC),
  KEY `fk_posts_user` (`userId`),
  CONSTRAINT `fk_posts_user` FOREIGN KEY (`userId`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `posts_ibfk_3` FOREIGN KEY (`timetableId`) REFERENCES `timetable` (`id`),
  CONSTRAINT `posts_ibfk_4` FOREIGN KEY (`subjectId`, `isLab`) REFERENCES `real_subjects` (`subjectId`, `isLab`),
  CONSTRAINT `posts_ibfk_5` FOREIGN KEY (`professorId`) REFERENCES `users` (`id`),
  CONSTRAINT `CONSTRAINT_1` CHECK (`timetableId` is not null and `timetableDate` is not null and `subjectId` is null and `isLab` is null and `professorId` is null or `timetableId` is null and `timetableDate` is null and `subjectId` is not null and `isLab` is not null and `professorId` is null or `timetableId` is null and `timetableDate` is null and `subjectId` is null and `isLab` is null and `professorId` is not null)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `real_subjects`
--

DROP TABLE IF EXISTS `real_subjects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `real_subjects` (
  `subjectId` smallint(5) unsigned NOT NULL,
  `isLab` tinyint(1) NOT NULL,
  PRIMARY KEY (`subjectId`,`isLab`),
  CONSTRAINT `real_subjects_ibfk_1` FOREIGN KEY (`subjectId`) REFERENCES `subjects` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `roles`
--

DROP TABLE IF EXISTS `roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `roles` (
  `id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `roleName` varchar(50) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `roleName` (`roleName`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `studyFields`
--

DROP TABLE IF EXISTS `studyFields`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `studyFields` (
  `id` uuid NOT NULL DEFAULT uuid(),
  `studyField` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `studyField` (`studyField`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `subjects`
--

DROP TABLE IF EXISTS `subjects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `subjects` (
  `id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=18 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `timetable`
--

DROP TABLE IF EXISTS `timetable`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `timetable` (
  `id` uuid NOT NULL DEFAULT uuid(),
  `classId` uuid DEFAULT NULL,
  `weekDay` enum('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') NOT NULL,
  `startDate` date NOT NULL,
  `endDate` date NOT NULL,
  `startTime` time NOT NULL,
  `endTime` time NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `classId` (`classId`,`weekDay`,`startDate`,`endDate`,`startTime`,`endTime`),
  CONSTRAINT `timetable_ibfk_1` FOREIGN KEY (`classId`) REFERENCES `classes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `timetable_professors`
--

DROP TABLE IF EXISTS `timetable_professors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `timetable_professors` (
  `lessonId` uuid NOT NULL,
  `professorId` uuid NOT NULL,
  PRIMARY KEY (`lessonId`,`professorId`),
  KEY `professorId` (`professorId`),
  KEY `idx_tp_lesson` (`lessonId`,`professorId`),
  CONSTRAINT `timetable_professors_ibfk_1` FOREIGN KEY (`lessonId`) REFERENCES `timetable` (`id`),
  CONSTRAINT `timetable_professors_ibfk_2` FOREIGN KEY (`professorId`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `timetable_subjects`
--

DROP TABLE IF EXISTS `timetable_subjects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `timetable_subjects` (
  `lessonId` uuid NOT NULL,
  `subjectId` smallint(5) unsigned NOT NULL,
  `isLab` tinyint(1) NOT NULL,
  PRIMARY KEY (`lessonId`,`subjectId`),
  KEY `subjectId` (`subjectId`,`isLab`),
  KEY `idx_ts_lesson` (`lessonId`,`subjectId`,`isLab`),
  CONSTRAINT `timetable_subjects_ibfk_1` FOREIGN KEY (`lessonId`) REFERENCES `timetable` (`id`),
  CONSTRAINT `timetable_subjects_ibfk_2` FOREIGN KEY (`subjectId`, `isLab`) REFERENCES `real_subjects` (`subjectId`, `isLab`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` uuid NOT NULL DEFAULT uuid(),
  `name` varchar(128) NOT NULL,
  `surname` varchar(128) NOT NULL,
  `username` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `roleId` smallint(5) unsigned NOT NULL DEFAULT 2,
  `userVersion` uuid NOT NULL DEFAULT uuid(),
  `classId` uuid DEFAULT NULL,
  `credentialsId` uuid DEFAULT NULL,
  `profileImageId` uuid DEFAULT NULL,
  `lastUpdated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `dateOfCreation` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  KEY `roleId` (`roleId`),
  KEY `classId` (`classId`),
  KEY `credentialsId` (`credentialsId`),
  CONSTRAINT `users_ibfk_1` FOREIGN KEY (`roleId`) REFERENCES `roles` (`id`),
  CONSTRAINT `users_ibfk_2` FOREIGN KEY (`classId`) REFERENCES `classes` (`id`),
  CONSTRAINT `users_ibfk_3` FOREIGN KEY (`credentialsId`) REFERENCES `credentials` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `votes`
--

DROP TABLE IF EXISTS `votes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `votes` (
  `id` uuid NOT NULL DEFAULT uuid(),
  `postId` uuid NOT NULL,
  `userId` uuid DEFAULT NULL,
  `value` tinyint(3) unsigned NOT NULL,
  `valueType` enum('burger','picker') NOT NULL,
  `dateOfCreation` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_votes_post_user` (`postId`,`userId`),
  KEY `fk_votes_user` (`userId`),
  CONSTRAINT `fk_votes_post` FOREIGN KEY (`postId`) REFERENCES `posts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_votes_user` FOREIGN KEY (`userId`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `chk_vote_value` CHECK (`value` between 0 and 10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-10-25 11:56:36
