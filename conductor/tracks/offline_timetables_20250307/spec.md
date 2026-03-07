# Spec: Offline Timetables Functionality

## Objective
To provide users with access to public transport timetables for Bratislava (MHD) even when an internet connection is unavailable.

## Goals
- Download and store timetable data locally (SQLite).
- Update local data when an internet connection is available.
- Provide a fast and reliable offline search for stops and schedules.

## Technical Requirements
- Integrate with existing TimetableDatabase.swift.
- Implement a data fetching and synchronization mechanism.
- Ensure efficient querying of offline schedules.
