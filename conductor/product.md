# Product Definition — Water Tracker

## Project Name

Water Tracker

## Description

A Mac app for logging and monitoring daily water consumption.

## Problem Statement

Users forget to drink enough water throughout the day.

## Target Users

Mac users who want to build a daily hydration habit.

## Key Goals

- Simple one-click logging, daily goal tracking, and gentle reminders
- Lightweight native Mac app — no account required, privacy-first
- Webcam tracking for detecting drinking water every X minutes (configurable interval, selectable camera)
- Bottle-finished tracking with configurable bottle sizes, so users tap when they finish a bottle and the app displays total water consumed (metric units only)

## Key Features

- **Circular progress ring** with wave fill animation and gradient stroke
- **Preset bottle size buttons** (250/350/500/750ml, configurable) for quick logging
- **Sound feedback** on log with button bounce animation
- **Confetti celebration** when daily goal is reached
- **Undo toast** after logging with visible Undo action
- **Dynamic menu bar icon** reflecting daily fill level (SF Symbol variable value)
- **Global keyboard shortcut** (Ctrl+Shift+W) for quick-logging from anywhere
- **Streak tracking** — flame icon with consecutive day count
- **Weekly bar chart** (Swift Charts) with color-coded completion bars
- **Settings window** with TabView (General, Goal & Bottles, Reminders, Camera)
- **Detection log** accessible in Camera settings tab
