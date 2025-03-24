# Kwisper

Kwisper is a macOS menubar application that allows you to record audio and transcribe it with a simple keyboard shortcut.

## Features

- Global keyboard shortcut to start/stop recording
- Audio recording from your system microphone
- Transcription using OpenAI's Whisper API
- Automatic insertion of transcribed text at cursor position
- Minimal resource usage and elegant UI

## Requirements

- macOS 11.0 or later
- Xcode 12.0 or later (for development)
- OpenAI API key (can be set via environment variable `OPENAI_API_KEY` or in the app settings)

## Building from Source

1. Clone the repository
2. Open `KwisperSwift/Kwisper.xcodeproj` in Xcode
3. Build and run the application

## Usage

1. Press and hold the keyboard shortcut (default: Command+Option+V)
2. Speak clearly into your microphone
3. Release the shortcut to stop recording
4. The transcribed text will be automatically inserted at your cursor position

## Configuration

1. Set your OpenAI API key using one of these methods:
   - Environment variable: `export OPENAI_API_KEY=your_api_key_here` (recommended for security)
   - In the app: Click the Kwisper icon in the menubar and enter your API key
2. Configure your preferred keyboard shortcut
3. Adjust other settings as needed

Using the environment variable approach keeps your API key more secure by not storing it in the app configuration files.

## Project Structure

```
KwisperSwift/
├── Kwisper.xcodeproj/
├── Kwisper/
│   ├── App/                  # Main application logic
│   ├── Core/                 # Core functionality
│   │   ├── Models/           # Data models
│   │   ├── Services/         # Service classes
│   │   └── Utils/            # Utility classes
│   ├── UI/                   # User interface components
│   │   ├── StatusBar/        # Status bar UI
│   │   └── Settings/         # Settings UI
│   ├── Resources/            # Resources like images and config files
│   └── Config/               # Configuration files
└── README.md                 # Project documentation
```

## License

[MIT License](LICENSE)