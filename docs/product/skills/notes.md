---
title: Notes
summary: Create, read, edit, and organise your notes through Chat.
tags: [skills, notes]
audience: user
surfaces: [app, website, internal-knowledge]
skill_id: notes
---

## What it does

The Notes skill gives sideBar access to your notes library from Chat. You can
ask sideBar to create notes, read existing notes, organise them into folders,
and manage the Scratchpad. sideBar can also work with your notes as context,
drafting new content, summarising, or cross-referencing with other things you
have saved.

## Actions

| Action | Description |
| --- | --- |
| Create note | Creates a new note, optionally in a specified folder |
| Edit note | Safely edits an existing note using the latest saved version |
| Get note | Reads the contents of a note into the conversation |
| List notes | Lists notes, optionally filtered by folder |
| Move note | Moves a note to a different folder |
| Pin note | Pins a note to the top of your notes list |
| Archive note | Archives a note, removing it from the main view |
| Delete note | Deletes a note from the main view |
| Download note | Exports a note as a plain text file |
| Create note folder | Creates a new folder |
| Rename note folder | Renames a folder |
| Move note folder | Moves a folder inside another folder |
| Delete note folder | Deletes a folder and its contents from the main view |
| Get scratchpad | Reads the current contents of your Scratchpad |
| Update scratchpad | Replaces the current Scratchpad content |
| Clear scratchpad | Clears the Scratchpad |

## When sideBar uses it

When your request involves creating, finding, or working with notes. Common triggers:

- Creating a note from something in the conversation ("Save this as a note")
- Reading or referencing an existing note ("What did I write about X?")
- Organising your notes library ("Move all my project notes into a folder called Work")
- Working with the Scratchpad ("Add this to my scratchpad")

## Current limitations

Note edits through Chat are block-based and use the latest saved note version.
That makes them safer, but it also means sideBar is not doing freeform cursor
editing inside the note editor. For broad rewrites, it may still be simpler to
draft a new version in Chat and review it before replacing larger sections.

## Requirements

- **Tier:** Standard (included, no installation needed)
- **API key:** None required

## How to enable

The Notes skill is enabled by default. To toggle it, go to **Settings → Skills**.

## Examples

> "Create a note called 'Book recommendations' and add the last three books we discussed."

> "What does my note on the Henderson project say?"

> "Summarise all my notes from this week into a single note."

> "Move my travel notes into a folder called Trips."

> "Add a quick note to my scratchpad — remember to call the dentist."
