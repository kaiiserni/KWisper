# KWisper

A macOS tray icon application that converts speech to text using OpenAI's Whisper API.

## Features

- Double-press Option/Alt key to start recording (press once shortly, then press and hold on second press), release to stop
- Automatic transcription using Whisper API
- Automatic clipboard paste of transcribed text
- System tray icon for easy access
- Configurable Whisper model and language settings

## Requirements

- macOS
- Python 3.8+
- OpenAI API key set as environment variable `OPENAI_API_KEY`

## Installation

1. Clone the repository
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Create a `config.yml` file with your settings:

```yaml
whisper:
  model: "whisper-1" # OpenAI Whisper model to use
  language: "en" # Language code for transcription
  prompt: "Not a native English speaker. Improve grammar where needed." # Optional prompt to guide transcription
```

## Usage

1. Set your OpenAI API key as an environment variable:

```bash
export OPENAI_API_KEY='your-api-key'
```

2. Run the application:

```bash
python kwisper.py
```

3. To start recording:
   - Press the Option/Alt key once shortly
   - Press and hold the Option/Alt key again
   - Release the Option/Alt key to stop recording and transcribe
