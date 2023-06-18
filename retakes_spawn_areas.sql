-- phpMyAdmin SQL Dump
-- version 4.9.5deb2
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Jun 18, 2023 at 04:04 PM
-- Server version: 10.3.38-MariaDB-0ubuntu0.20.04.1
-- PHP Version: 7.4.3-4ubuntu2.18

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `csgo_retakes`
--

-- --------------------------------------------------------

--
-- Table structure for table `retakes_spawn_areas`
--

CREATE TABLE `retakes_spawn_areas` (
  `map_name` varchar(128) NOT NULL,
  `nav_area_id` int(11) NOT NULL,
  `bombsite_index` int(11) NOT NULL,
  `nav_mesh_area_team` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `retakes_spawn_areas`
--

INSERT INTO `retakes_spawn_areas` (`map_name`, `nav_area_id`, `bombsite_index`, `nav_mesh_area_team`) VALUES
('de_dust2', 4140, 0, 0),
('de_dust2', 4932, 0, 0),
('de_dust2', 4933, 0, 0),
('de_dust2', 4934, 0, 0),
('de_dust2', 9000, 0, 0),
('de_dust2', 8798, 0, 0),
('de_dust2', 4946, 0, 0),
('de_dust2', 4939, 0, 0),
('de_dust2', 4938, 0, 0),
('de_dust2', 8797, 0, 0),
('de_dust2', 4940, 0, 0),
('de_dust2', 1794, 0, 0),
('de_dust2', 8919, 0, 0),
('de_dust2', 4923, 0, 0),
('de_dust2', 1399, 0, 0),
('de_dust2', 1409, 0, 0),
('de_dust2', 1724, 0, 0),
('de_dust2', 1726, 0, 0),
('de_dust2', 1730, 0, 0),
('de_dust2', 8253, 0, 0),
('de_dust2', 8773, 0, 0),
('de_dust2', 4171, 0, 0),
('de_dust2', 4293, 0, 0),
('de_dust2', 4220, 0, 0),
('de_dust2', 4952, 0, 0),
('de_dust2', 4951, 0, 0),
('de_dust2', 4215, 0, 0),
('de_dust2', 8849, 0, 1),
('de_dust2', 8840, 0, 1),
('de_dust2', 8787, 0, 1),
('de_dust2', 8924, 0, 1),
('de_dust2', 8789, 0, 1),
('de_dust2', 67, 0, 1),
('de_dust2', 1713, 0, 1),
('de_dust2', 5221, 0, 1),
('de_dust2', 1082, 0, 1),
('de_dust2', 1083, 0, 1),
('de_dust2', 5226, 0, 1),
('de_dust2', 6695, 0, 1),
('de_dust2', 5220, 0, 1),
('de_dust2', 1898, 0, 1),
('de_dust2', 9105, 0, 1),
('de_dust2', 9049, 0, 1),
('de_dust2', 9107, 0, 1),
('de_dust2', 1892, 0, 1),
('de_dust2', 5222, 0, 1),
('de_dust2', 1819, 0, 1),
('de_dust2', 5253, 0, 1),
('de_dust2', 4010, 1, 0),
('de_dust2', 8803, 1, 0),
('de_dust2', 1651, 1, 0),
('de_dust2', 1642, 1, 0),
('de_dust2', 1644, 1, 0),
('de_dust2', 7863, 1, 0),
('de_dust2', 1652, 1, 0),
('de_dust2', 1685, 1, 0),
('de_dust2', 6806, 1, 0),
('de_dust2', 1573, 1, 0),
('de_dust2', 1571, 1, 0),
('de_dust2', 60, 1, 0),
('de_dust2', 7968, 1, 0),
('de_dust2', 7969, 1, 0),
('de_dust2', 6803, 1, 0),
('de_dust2', 6812, 1, 0),
('de_dust2', 6831, 1, 0),
('de_dust2', 3743, 1, 0),
('de_dust2', 3740, 1, 0),
('de_dust2', 8546, 1, 0),
('de_dust2', 8805, 1, 0),
('de_dust2', 6807, 1, 0),
('de_dust2', 6813, 1, 0),
('de_dust2', 7931, 1, 0),
('de_dust2', 6841, 1, 0),
('de_dust2', 6583, 1, 1),
('de_dust2', 3951, 1, 1),
('de_dust2', 8205, 1, 1),
('de_dust2', 212, 1, 1),
('de_dust2', 1391, 1, 1),
('de_dust2', 3777, 1, 1),
('de_dust2', 3779, 1, 1),
('de_dust2', 8300, 1, 1),
('de_dust2', 8303, 1, 1),
('de_dust2', 1287, 1, 1),
('de_dust2', 7822, 1, 1),
('de_dust2', 5241, 1, 1),
('de_dust2', 5225, 1, 1),
('de_dust2', 66, 1, 1),
('de_dust2', 8775, 1, 1),
('de_dust2', 123, 1, 1),
('de_dust2', 5226, 1, 1),
('de_dust2', 5221, 1, 1),
('de_dust2', 6695, 1, 1),
('de_dust2', 5220, 1, 1),
('de_dust2', 8531, 1, 1),
('de_dust2', 5356, 1, 1),
('de_dust2', 8534, 1, 1),
('de_dust2', 5230, 1, 1),
('de_dust2', 5256, 1, 1),
('de_dust2', 5284, 1, 1),
('de_dust2', 5253, 1, 1),
('de_dust2', 8821, 1, 1),
('de_dust2', 8823, 1, 1),
('de_dust2', 9013, 1, 1),
('de_dust2', 1801, 1, 1);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
