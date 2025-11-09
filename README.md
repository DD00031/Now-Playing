<div align="center">
    <img src="Now-Playing/Icons/Now Playing-macOS-Default-1024x1024@1x.png" width=200 height=200>
    <h1>Now Playing</h1>
</div>

A simple, beautiful "Now Playing" app for macOS that shows the currently playing song from all your favorite music players. Built entirely in SwiftUI.

![Now Playing App Screenshot](screenshot.png)

## Features

- Displays the metadata of the currently playing media, along with the album art
- Shows a real-time playback progress timer that updates every second
- Beautiful, modern UI with a blurred, adaptive gradient
- Automatically detects and switches between multiple music players
- System-wide playback controls (Play/Pause, Next, Previous)

> **Note:** Retrieving album art for Spotify requires an active internet connection.

> **Note:** Integration with Foobar2000 requires a [component](https://github.com/DD00031/now-playing-foobar). 

## Supported Players

- Apple Music
- Spotify
- Foobar2000 (via component, see setup below)

## Installation

**System Requirements:**  
- macOS **13 (Ventura)** or later  

Download the "Now-Playing.dmg" file from the [latest release](https://github.com/DD00031/Now-Playing/releases/latest). Open it and move the app into your `Applications` folder.


> [!IMPORTANT]
>
> Apple will flag this app as it is not signed by an registered developer, this doesn't mean the app is not safe. To use the app follow the steps below
> 1. Click **OK** to close the popup.
> 2. Open **System Settings** > **Privacy & Security**.
> 3. Scroll down and click **Open Anyway**.
> 4. Confirm your choice when prompted.
>
> You only need to do this once.

## Setup

After downloading and installing the app, you must grant it permissions to function.

On the first run, macOS will ask for several permissions: `Accessibility` and `Automations`. You must approve them for the app to work.

After this the app will work for Spotify and Apple Music. To use the app with Foobar2000 you will need to install a component that caches the data of the currently playing media. 

For download and setup instructions: https://github.com/DD00031/now-playing-foobar

## License
Now Playing is available under the GPL-3.0 license.

## Disclaimer
This project was built with the help of Google Gemini 2.5 Pro and Claude Sonnet 4.5 as a personal solution. I won't be actively maintaining this project, but feel free to open an issue or submit a pull request!
