import os
import time
import threading
import logging
import tempfile
import sounddevice as sd
import soundfile as sf
import numpy as np
from pynput import keyboard
import rumps
from openai import OpenAI
import pyperclip
import objc
from Foundation import NSObject, NSThread, NSRunLoop
from AppKit import (NSPasteboard, NSStringPboardType,
                    NSWorkspace, NSScreen, NSWindow,
                    NSBackingStoreBuffered, NSBorderlessWindowMask,
                    NSColor, NSFloatingWindowLevel, NSWindowStyleMaskTitled,
                    NSTextField, NSMakeRect, NSCenterTextAlignment,
                    NSFont, NSVisualEffectView, NSVisualEffectBlendingModeBehindWindow,
                    NSVisualEffectMaterialHUDWindow, NSApplication)
import yaml


class KwisperApp(rumps.App):
    def __init__(self, config):
        super().__init__("🎤", quit_button=None)
        logging.basicConfig(level=logging.INFO,
                            format='%(asctime)s - %(levelname)s - %(message)s')
        self.is_transcribing = False

        # Load config settings
        self.config = config
        self.model = self.config["whisper"]["model"]
        self.language = self.config["whisper"]["language"]
        self.prompt = self.config["whisper"].get("prompt", "")
        self.restore_clipboard = self.config.get("clipboard", {}).get("restore_previous", True)
        self.previous_clipboard_content = None

        self.recording = False
        self.audio_data = []
        self.sample_rate = 44100
        self.client = OpenAI()
        self.recording_thread = None
        self.opt_pressed = False
        self.last_opt_press_time = 0
        self.last_opt_event_time = 0
        self.waiting_for_second_tap = False
        self.opt_tap_threshold = 1.0  # seconds to wait for second tap
        self.min_event_interval = 0.05  # minimum time between key events
        self.previous_window = None
        self.recording_window = None
        self.status_label = None

        self.setup_keyboard_listener()
        self.create_window()
        self._setup_window_content()
        self.recording_window.orderOut_(None)  # hide initially

    def create_window(self):
        screen = NSScreen.mainScreen()
        screen_rect = screen.frame()
        window_width = 280
        window_height = 120
        x = (screen_rect.size.width - window_width) / 2
        y = (screen_rect.size.height - window_height) / 2

        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            ((x, y), (window_width, window_height)),
            NSWindowStyleMaskTitled | NSBorderlessWindowMask,
            NSBackingStoreBuffered,
            False
        )
        self.recording_window = window

    def _setup_window_content(self):
        self.recording_window.setTitle_("KWisper")

        # Create visual effect view (blur effect)
        content_view = NSVisualEffectView.alloc().initWithFrame_(
            self.recording_window.contentView().frame())
        content_view.setMaterial_(NSVisualEffectMaterialHUDWindow)
        content_view.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        content_view.setState_(1)

        # Create and configure the label
        label = NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, 40, 240, 40))
        label.setEditable_(False)
        label.setBezeled_(False)
        label.setDrawsBackground_(False)
        label.setTextColor_(NSColor.whiteColor())
        label.setFont_(NSFont.boldSystemFontOfSize_(16))
        label.setAlignment_(NSCenterTextAlignment)
        self.status_label = label
        label.setStringValue_(
            "🎙️ KWisper Recording...\nRelease option to stop")

        # Add label to content view
        content_view.addSubview_(label)

        # Set content view
        self.recording_window.setContentView_(content_view)
        self.recording_window.setAlphaValue_(0.95)
        self.recording_window.setLevel_(NSFloatingWindowLevel)
        self.recording_window.setHasShadow_(True)

    def setup_keyboard_listener(self):
        self.keyboard_listener = keyboard.Listener(
            on_press=self.on_press,
            on_release=self.on_release
        )
        self.keyboard_listener.start()

    def on_press(self, key):
        try:
            key_str = str(key)
            current_time = time.time()

            # Handle Escape key during recording or transcribing
            if key == keyboard.Key.esc and (self.recording or self.is_transcribing):
                if self.recording:
                    self.stop_recording()
                self.is_transcribing = False
                self.recording_window.orderOut_(None)
                return

            # Process Option key events
            if '<58>' not in key_str and 'Key.alt' not in key_str:
                return

            # Prevent duplicate events
            if current_time - self.last_opt_event_time < self.min_event_interval:
                return

            self.last_opt_event_time = current_time

            if not self.opt_pressed:
                if not self.waiting_for_second_tap:
                    # First tap
                    self.last_opt_press_time = current_time
                    self.waiting_for_second_tap = True
                else:
                    # Check second tap
                    time_since_last = current_time - self.last_opt_press_time
                    if time_since_last <= self.opt_tap_threshold:
                        if not self.recording:
                            self.start_recording()
                    else:
                        # New first tap
                        self.last_opt_press_time = current_time
                        self.waiting_for_second_tap = True

                self.opt_pressed = True
        except Exception as e:
            logging.error(f"Error in on_press: {str(e)}")

    def on_release(self, key):
        try:
            key_str = str(key)
            current_time = time.time()

            # Process Option key events
            if '<58>' not in key_str and 'Key.alt' not in key_str:
                return

            # Prevent duplicate events
            if current_time - self.last_opt_event_time < self.min_event_interval:
                return

            self.last_opt_event_time = current_time

            if self.opt_pressed:
                self.opt_pressed = False

                if self.recording:
                    self.stop_recording()
                    self.transcribe_and_paste()
                elif self.waiting_for_second_tap:
                    time_since_last = current_time - self.last_opt_press_time
                    if time_since_last > self.opt_tap_threshold:
                        self.waiting_for_second_tap = False
        except Exception as e:
            logging.error(f"Error in on_release: {str(e)}")

    def start_recording(self):
        self.recording = True
        self.audio_data = []
        self.title = "🔴"
        logging.info("Started recording")

        # Store the current active window
        self.previous_window = NSWorkspace.sharedWorkspace().activeApplication()

        # Show and activate recording window
        NSApp = NSApplication.sharedApplication()
        NSApp.activateIgnoringOtherApps_(True)
        self.recording_window.setLevel_(NSFloatingWindowLevel)
        self.recording_window.makeKeyAndOrderFront_(None)
        self.recording_window.orderFrontRegardless()
        self.status_label.setStringValue_(
            "🎙️ KWisper Recording...\nRelease option to stop")

        def record_audio():
            with sd.InputStream(samplerate=self.sample_rate, channels=1, callback=self.audio_callback):
                while self.recording:
                    time.sleep(0.1)

        self.recording_thread = threading.Thread(target=record_audio)
        self.recording_thread.start()

    def audio_callback(self, indata, frames, time_info, status):
        if self.recording:
            self.audio_data.append(indata.copy())

    def stop_recording(self):
        self.recording = False
        self.title = "🎤"
        logging.info("Stopped recording")

        # Return to previous window
        if self.previous_window:
            NSWorkspace.sharedWorkspace().launchApplication_(
                self.previous_window['NSApplicationName']
            )

        if self.recording_thread:
            self.recording_thread.join()

    def transcribe_and_paste(self):
        if not self.audio_data:
            # Hide the window if nothing recorded
            self.recording_window.orderOut_(None)
            return

        def transcribe_work():
            self.is_transcribing = True
            audio_data = np.concatenate(self.audio_data, axis=0)

            # Save to temporary WAV file
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_audio:
                sf.write(temp_audio.name, audio_data, self.sample_rate)

                try:
                    # Use config-provided model, language, and prompt
                    with open(temp_audio.name, 'rb') as audio_file:
                        transcript = self.client.audio.transcriptions.create(
                            model=self.model,
                            file=audio_file,
                            language=self.language,
                            prompt=self.prompt
                        )

                    if transcript.text and self.is_transcribing:
                        text = transcript.text.strip()
                        logging.info("Transcription completed")

                        def complete_transcription():
                            try:
                                # Hide the window
                                self.recording_window.orderOut_(None)

                                # Switch back to previous app and paste
                                if self.previous_window:
                                    NSWorkspace.sharedWorkspace().launchApplication_(
                                        self.previous_window['NSApplicationName']
                                    )
                                    time.sleep(0.3)

                                self.paste_text(text)
                                logging.info(
                                    "Transcription completed and pasted")

                            except Exception as e:
                                logging.error(
                                    f"Error in complete_transcription: {str(e)}")

                        complete_transcription()

                finally:
                    os.unlink(temp_audio.name)
                    self.is_transcribing = False

        # Show status before starting transcription
        self.recording_window.orderFrontRegardless()
        self.recording_window.makeKeyAndOrderFront_(None)
        self.status_label.setStringValue_("✨ KWisper Transcribing...")
        NSApplication.sharedApplication().activateIgnoringOtherApps_(True)
        logging.info("Starting transcription")

        # Start transcription in background
        threading.Thread(target=transcribe_work).start()

    def paste_text(self, text):
        pasteboard = NSPasteboard.generalPasteboard()
        
        # Store previous clipboard content if restoration is enabled
        if self.restore_clipboard:
            self.previous_clipboard_content = pasteboard.stringForType_(NSStringPboardType)
        
        # Set new content
        pasteboard.clearContents()
        pasteboard.setString_forType_(text, NSStringPboardType)

        # Give the pasteboard a moment
        time.sleep(0.1)

        # Simulate Cmd+V
        kb = keyboard.Controller()
        kb.press(keyboard.Key.cmd)
        time.sleep(0.05)
        kb.press('v')
        time.sleep(0.05)
        kb.release('v')
        time.sleep(0.05)
        kb.release(keyboard.Key.cmd)

        # Restore previous clipboard content if enabled
        if self.restore_clipboard and self.previous_clipboard_content:
            time.sleep(0.1)  # Give a moment for the paste to complete
            pasteboard.clearContents()
            pasteboard.setString_forType_(self.previous_clipboard_content, NSStringPboardType)

    @rumps.clicked("Quit")
    def quit_app(self, _):
        if self.recording_window:
            self.recording_window.orderOut_(None)
            self.recording_window = None
        self.keyboard_listener.stop()
        rumps.quit_application()


if __name__ == "__main__":
    if not os.getenv("OPENAI_API_KEY"):
        print("Error: OPENAI_API_KEY environment variable not set")
        exit(1)

    # Load configuration from YAML
    with open("config.yml", "r") as f:
        cfg = yaml.safe_load(f)

    app = KwisperApp(cfg)
    app.run()

