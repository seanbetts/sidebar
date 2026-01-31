---
title: "Voice Chat Implementation Plan"
description: "Plan for voice chat feature implementation."
---

# Voice Chat Implementation Plan

**Date**: 2025-12-28
**Feature**: Voice-based conversations with Claude using OpenAI Realtime STT + TTS

---

## Overview

Add seamless voice conversation capability to sideBar chat, allowing users to speak to Claude and receive spoken responses. Voice integrates with existing text chat - users can switch between voice and text input freely within the same conversation.

### Architecture

```
┌─────────────┐
│   Browser   │
│             │
│  Mic Input  │──WebRTC──┐
│             │          │
│  Audio Out  │◄────────┐│
└─────────────┘         ││
                        ││
                   ┌────▼▼──────────┐
                   │ OpenAI Realtime│
                   │   (STT only)   │
                   └────┬───────────┘
                        │ Transcript
                        ▼
                ┌──────────────────┐
                │  FastAPI Backend │
                │                  │
                │  Claude Messages │◄── Existing tools
                │  API + Tools     │    & context
                └────┬─────────────┘
                     │ Text response
                     ▼
                ┌──────────────────┐
                │   OpenAI TTS     │
                │    (tts-1)       │
                └────┬─────────────┘
                     │ Audio stream
                     ▼
                ┌─────────────┐
                │   Browser   │
                │  Audio Out  │
                └─────────────┘
```

**Key Points:**
- OpenAI Realtime handles STT only (WebRTC from browser)
- Claude stays in middle for reasoning + tools (unchanged)
- OpenAI TTS converts responses to speech
- Voice and text chat share same conversation_id

---

## Requirements Summary

### Core Behavior
- ✅ Seamless switching between voice and text mid-conversation
- ✅ Voice transcripts appear in chat history
- ✅ Text responses read aloud when in voice mode
- ✅ Shared conversation_id and context between voice/text
- ✅ Full barge-in support (finish current sentence)
- ✅ Tool execution feedback (speak tool names + "thinking" sound)
- ✅ Errors spoken aloud

### Technical Specs
- ✅ OpenAI tts-1 model (balance of speed/quality/cost)
- ✅ Default voice for all users (pick one)
- ✅ No audio storage (transcripts only)
- ✅ Desktop-first (Chrome, Safari, Edge)
- ✅ Fallback to text-only if WebRTC unavailable
- ✅ English only

### UX Design
- ✅ Voice button next to send button in chat input
- ✅ Real-time transcript display while speaking
- ✅ Toggle activation (click to start, click to stop)
- ✅ Include open note/website context
- ✅ Full scratchpad and memory integration

---

## Implementation Phases

### Phase 1: Backend - Ephemeral Tokens & Voice Session (2-3 hours)

Create backend endpoints for OpenAI Realtime session management.

#### 1.1 Add OpenAI Client Configuration

**File**: `/backend/api/config.py`

Add OpenAI API key (if not already present):

```python
class Settings(BaseSettings):
    # ... existing settings ...

    # OpenAI (for voice STT/TTS)
    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1"
    openai_realtime_model: str = "gpt-4o-realtime-preview-2024-12-17"
    openai_tts_model: str = "tts-1"
    openai_tts_voice: str = "alloy"  # Options: alloy, echo, fable, onyx, nova, shimmer
```

**Environment variables** (`.env`):
```bash
OPENAI_API_KEY=sk-...
OPENAI_TTS_VOICE=alloy
```

#### 1.2 Create Voice Session Service

**New file**: `/backend/api/services/voice_session_service.py`

```python
"""Voice session management for OpenAI Realtime."""
import httpx
from datetime import datetime, timedelta
from api.config import settings


class VoiceSessionService:
    """Manages OpenAI Realtime ephemeral session tokens."""

    @staticmethod
    async def create_ephemeral_token() -> dict:
        """
        Create ephemeral token for OpenAI Realtime WebRTC connection.

        Tokens are short-lived (15 minutes) and scoped to STT only.

        Returns:
            Dictionary containing:
                - token (str): Ephemeral client token
                - expires_at (str): ISO 8601 expiry timestamp
                - model (str): Realtime model name

        Raises:
            HTTPException: If OpenAI API fails
        """
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{settings.openai_base_url}/realtime/sessions",
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": settings.openai_realtime_model,
                    "voice": settings.openai_tts_voice
                },
                timeout=10.0
            )
            response.raise_for_status()
            data = response.json()

            # Token expires in 15 minutes
            expires_at = datetime.utcnow() + timedelta(minutes=15)

            return {
                "token": data["client_secret"]["value"],
                "expires_at": expires_at.isoformat(),
                "model": settings.openai_realtime_model
            }
```

#### 1.3 Create Voice Session Endpoint

**New file**: `/backend/api/routers/voice.py`

```python
"""Voice chat endpoints for STT/TTS integration."""
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
import httpx

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.voice_session_service import VoiceSessionService
from api.config import settings


router = APIRouter(prefix="/voice", tags=["voice"])


@router.post("/session")
async def create_voice_session(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token)
):
    """
    Create OpenAI Realtime session for voice input.

    Generates a short-lived ephemeral token for browser to connect
    to OpenAI Realtime via WebRTC for speech-to-text.

    Returns:
        Dictionary with:
            - token: Ephemeral client token (15min lifetime)
            - expires_at: ISO timestamp of expiry
            - model: Realtime model name

    Raises:
        HTTPException: 500 if OpenAI API fails
    """
    try:
        session = await VoiceSessionService.create_ephemeral_token()
        return session
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create voice session: {str(e)}"
        )


@router.post("/tts")
async def text_to_speech(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token)
):
    """
    Convert text to speech using OpenAI TTS.

    Streams audio back to client as it's generated.

    Body:
        {
            "text": "Text to speak",
            "voice": "alloy"  // Optional, defaults to configured voice
        }

    Returns:
        StreamingResponse with audio/mpeg content

    Raises:
        HTTPException: 400 if text is empty
        HTTPException: 500 if OpenAI TTS fails
    """
    text = request.get("text", "").strip()
    voice = request.get("voice", settings.openai_tts_voice)

    if not text:
        raise HTTPException(status_code=400, detail="text is required")

    try:
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{settings.openai_base_url}/audio/speech",
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": settings.openai_tts_model,
                    "input": text,
                    "voice": voice,
                    "response_format": "mp3"
                },
                timeout=30.0
            ) as response:
                response.raise_for_status()

                async def audio_stream():
                    async for chunk in response.aiter_bytes(chunk_size=4096):
                        yield chunk

                return StreamingResponse(
                    audio_stream(),
                    media_type="audio/mpeg",
                    headers={
                        "Cache-Control": "no-cache",
                        "X-Content-Type-Options": "nosniff"
                    }
                )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"TTS failed: {str(e)}"
        )
```

#### 1.4 Register Voice Router

**File**: `/backend/api/main.py`

```python
from api.routers import voice  # Add import

# ... existing code ...

app.include_router(voice.router, prefix="/api")
```

#### 1.5 Update Requirements

**File**: `/backend/requirements.txt`

Add if not present:
```
httpx>=0.27.0  # For async HTTP to OpenAI
```

---

### Phase 2: Frontend - WebRTC Integration (3-4 hours)

Integrate OpenAI Realtime WebRTC connection for speech-to-text.

#### 2.1 Create Voice Session Store

**New file**: `/frontend/src/lib/stores/voice.ts`

```typescript
import { writable } from 'svelte/store';

export type VoiceState =
  | 'idle'          // Not in voice mode
  | 'connecting'    // Establishing WebRTC connection
  | 'listening'     // Mic active, transcribing
  | 'processing'    // Sent to Claude, waiting
  | 'speaking'      // Playing TTS response
  | 'error';        // Error state

interface VoiceStore {
  state: VoiceState;
  isActive: boolean;        // Voice mode enabled
  transcript: string;       // Current partial transcript
  finalTranscript: string;  // Last completed transcript
  error: string | null;
}

function createVoiceStore() {
  const { subscribe, set, update } = writable<VoiceStore>({
    state: 'idle',
    isActive: false,
    transcript: '',
    finalTranscript: '',
    error: null
  });

  return {
    subscribe,
    setState: (state: VoiceState) => update(s => ({ ...s, state })),
    setTranscript: (transcript: string) => update(s => ({ ...s, transcript })),
    setFinalTranscript: (finalTranscript: string) =>
      update(s => ({ ...s, finalTranscript, transcript: '' })),
    setError: (error: string) => update(s => ({ ...s, error, state: 'error' })),
    setActive: (isActive: boolean) => update(s => ({ ...s, isActive })),
    reset: () => set({
      state: 'idle',
      isActive: false,
      transcript: '',
      finalTranscript: '',
      error: null
    })
  };
}

export const voiceStore = createVoiceStore();
```

#### 2.2 Create Realtime WebRTC Client

**New file**: `/frontend/src/lib/services/realtime-client.ts`

```typescript
import { voiceStore } from '$lib/stores/voice';

export class RealtimeClient {
  private peerConnection: RTCPeerConnection | null = null;
  private dataChannel: RTCDataChannel | null = null;
  private audioStream: MediaStream | null = null;
  private ephemeralToken: string | null = null;

  async connect(): Promise<void> {
    try {
      voiceStore.setState('connecting');

      // 1. Get ephemeral token from backend
      const response = await fetch('/api/voice/session', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('bearer_token')}`
        }
      });

      if (!response.ok) {
        throw new Error('Failed to create voice session');
      }

      const session = await response.json();
      this.ephemeralToken = session.token;

      // 2. Get microphone access
      this.audioStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });

      // 3. Create peer connection
      this.peerConnection = new RTCPeerConnection();

      // 4. Add audio track
      this.audioStream.getTracks().forEach(track => {
        this.peerConnection!.addTrack(track, this.audioStream!);
      });

      // 5. Create data channel for receiving transcripts
      this.dataChannel = this.peerConnection.createDataChannel('oai-events');

      this.dataChannel.onmessage = (event) => {
        this.handleRealtimeEvent(JSON.parse(event.data));
      };

      // 6. Create and send offer
      const offer = await this.peerConnection.createOffer();
      await this.peerConnection.setLocalDescription(offer);

      // 7. Send offer to OpenAI Realtime
      const baseUrl = 'https://api.openai.com/v1/realtime';
      const model = 'gpt-4o-realtime-preview-2024-12-17';

      const sdpResponse = await fetch(`${baseUrl}?model=${model}`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.ephemeralToken}`,
          'Content-Type': 'application/sdp'
        },
        body: offer.sdp
      });

      if (!sdpResponse.ok) {
        throw new Error('Failed to connect to OpenAI Realtime');
      }

      // 8. Set remote description
      const answer = await sdpResponse.text();
      await this.peerConnection.setRemoteDescription({
        type: 'answer',
        sdp: answer
      });

      voiceStore.setState('listening');
    } catch (error) {
      console.error('Realtime connection failed:', error);
      voiceStore.setError(error instanceof Error ? error.message : 'Connection failed');
      this.disconnect();
    }
  }

  private handleRealtimeEvent(event: any): void {
    const type = event.type;

    switch (type) {
      case 'input_audio_buffer.speech_started':
        // User started speaking
        voiceStore.setState('listening');
        break;

      case 'input_audio_buffer.speech_stopped':
        // User stopped speaking
        break;

      case 'conversation.item.input_audio_transcription.delta':
        // Partial transcript
        voiceStore.setTranscript(event.delta);
        break;

      case 'conversation.item.input_audio_transcription.completed':
        // Final transcript - send to Claude
        voiceStore.setFinalTranscript(event.transcript);
        this.onTranscriptComplete?.(event.transcript);
        break;

      case 'error':
        voiceStore.setError(event.error?.message || 'Realtime error');
        break;
    }
  }

  disconnect(): void {
    // Close data channel
    if (this.dataChannel) {
      this.dataChannel.close();
      this.dataChannel = null;
    }

    // Close peer connection
    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
    }

    // Stop audio stream
    if (this.audioStream) {
      this.audioStream.getTracks().forEach(track => track.stop());
      this.audioStream = null;
    }

    voiceStore.setState('idle');
  }

  // Callback when transcript is complete
  onTranscriptComplete: ((transcript: string) => void) | null = null;
}
```

#### 2.3 Create TTS Audio Player

**New file**: `/frontend/src/lib/services/tts-player.ts`

```typescript
import { voiceStore } from '$lib/stores/voice';

export class TTSPlayer {
  private audio: HTMLAudioElement | null = null;
  private abortController: AbortController | null = null;

  async play(text: string): Promise<void> {
    try {
      voiceStore.setState('speaking');

      // Abort any ongoing TTS
      this.stop();

      this.abortController = new AbortController();

      // Fetch TTS audio stream
      const response = await fetch('/api/voice/tts', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('bearer_token')}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ text }),
        signal: this.abortController.signal
      });

      if (!response.ok) {
        throw new Error('TTS failed');
      }

      // Convert stream to blob
      const blob = await response.blob();
      const audioUrl = URL.createObjectURL(blob);

      // Play audio
      this.audio = new Audio(audioUrl);

      this.audio.onended = () => {
        URL.revokeObjectURL(audioUrl);
        voiceStore.setState('listening');
        this.audio = null;
      };

      this.audio.onerror = () => {
        voiceStore.setError('Audio playback failed');
        this.audio = null;
      };

      await this.audio.play();
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        // Intentionally aborted (barge-in)
        return;
      }
      console.error('TTS playback failed:', error);
      voiceStore.setError(error instanceof Error ? error.message : 'TTS failed');
    }
  }

  stop(): void {
    // Abort fetch
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = null;
    }

    // Stop audio
    if (this.audio) {
      this.audio.pause();
      this.audio = null;
    }

    voiceStore.setState('listening');
  }

  isPlaying(): boolean {
    return this.audio !== null && !this.audio.paused;
  }
}
```

---

### Phase 3: Frontend - Voice UI Component (3-4 hours)

Create voice chat UI integrated with existing chat interface.

#### 3.1 Create Voice Button Component

**New file**: `/frontend/src/lib/components/chat/VoiceButton.svelte`

```svelte
<script lang="ts">
  import { Mic, MicOff } from 'lucide-svelte';
  import { Button } from '$lib/components/ui/button';
  import { voiceStore } from '$lib/stores/voice';

  export let onToggle: () => void;
  export let disabled = false;

  $: isActive = $voiceStore.isActive;
  $: state = $voiceStore.state;
</script>

<Button
  size="icon"
  variant={isActive ? 'default' : 'ghost'}
  onclick={onToggle}
  disabled={disabled || state === 'connecting'}
  aria-label={isActive ? 'Stop voice input' : 'Start voice input'}
  title={isActive ? 'Stop voice input' : 'Start voice input'}
  class="voice-button"
  class:active={isActive}
  class:listening={state === 'listening'}
  class:speaking={state === 'speaking'}
>
  {#if isActive}
    <Mic size={16} />
  {:else}
    <MicOff size={16} />
  {/if}
</Button>

<style>
  :global(.voice-button.active) {
    background-color: var(--color-primary);
    color: white;
  }

  :global(.voice-button.listening) {
    animation: pulse 2s ease-in-out infinite;
  }

  :global(.voice-button.speaking) {
    opacity: 0.7;
  }

  @keyframes pulse {
    0%, 100% {
      opacity: 1;
    }
    50% {
      opacity: 0.6;
    }
  }
</style>
```

#### 3.2 Create Real-time Transcript Display

**New file**: `/frontend/src/lib/components/chat/VoiceTranscript.svelte`

```svelte
<script lang="ts">
  import { voiceStore } from '$lib/stores/voice';
  import { fade } from 'svelte/transition';

  $: transcript = $voiceStore.transcript;
  $: state = $voiceStore.state;
</script>

{#if transcript && state === 'listening'}
  <div class="voice-transcript" transition:fade={{ duration: 200 }}>
    <div class="transcript-label">You're saying:</div>
    <div class="transcript-text">{transcript}</div>
  </div>
{/if}

<style>
  .voice-transcript {
    position: absolute;
    bottom: 100%;
    left: 0;
    right: 0;
    margin-bottom: 0.5rem;
    padding: 0.75rem 1rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  }

  .transcript-label {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
    margin-bottom: 0.25rem;
  }

  .transcript-text {
    font-size: 0.9rem;
    color: var(--color-foreground);
    font-style: italic;
  }
</style>
```

#### 3.3 Integrate Voice into ChatInput

**File**: `/frontend/src/lib/components/chat/ChatInput.svelte`

Add voice integration:

```svelte
<script lang="ts">
  // ... existing imports ...
  import VoiceButton from './VoiceButton.svelte';
  import VoiceTranscript from './VoiceTranscript.svelte';
  import { RealtimeClient } from '$lib/services/realtime-client';
  import { TTSPlayer } from '$lib/services/tts-player';
  import { voiceStore } from '$lib/stores/voice';

  // ... existing props ...

  let realtimeClient: RealtimeClient | null = null;
  let ttsPlayer = new TTSPlayer();

  async function toggleVoice() {
    const isActive = $voiceStore.isActive;

    if (isActive) {
      // Stop voice mode
      realtimeClient?.disconnect();
      realtimeClient = null;
      ttsPlayer.stop();
      voiceStore.setActive(false);
    } else {
      // Start voice mode
      realtimeClient = new RealtimeClient();

      // Handle completed transcripts
      realtimeClient.onTranscriptComplete = async (transcript: string) => {
        // Send to chat as if user typed it
        await handleVoiceInput(transcript);
      };

      await realtimeClient.connect();
      voiceStore.setActive(true);
    }
  }

  async function handleVoiceInput(transcript: string) {
    voiceStore.setState('processing');

    // Send to backend (reuse existing onsend)
    await onsend(transcript);

    // Response will come through normal chat flow
    // We'll intercept it to speak aloud
  }

  // ... existing code ...
</script>

<div class="chat-input-container">
  <VoiceTranscript />

  <!-- Existing input UI -->

  <div class="actions">
    <VoiceButton onToggle={toggleVoice} disabled={disabled} />
    <!-- Existing send button -->
  </div>
</div>

<style>
  .chat-input-container {
    position: relative;
  }

  .actions {
    display: flex;
    gap: 0.5rem;
    align-items: center;
  }
</style>
```

---

### Phase 4: Voice/Text Integration (2-3 hours)

Connect voice responses to TTS and handle barge-in.

#### 4.1 Update Chat Store for Voice

**File**: `/frontend/src/lib/stores/chat.ts`

Add voice response handling:

```typescript
// ... existing imports ...
import { voiceStore } from './voice';

// ... existing store ...

// Add method to handle voice responses
function handleAssistantResponse(messageId: string, content: string) {
  // If in voice mode, speak the response
  if (get(voiceStore).isActive) {
    const ttsPlayer = new TTSPlayer();
    ttsPlayer.play(content);
  }
}

// Hook into existing message completion
// When assistant message is complete, check if voice is active
```

#### 4.2 Implement Barge-In

**File**: `/frontend/src/lib/services/realtime-client.ts`

Add barge-in detection:

```typescript
private handleRealtimeEvent(event: any): void {
  const type = event.type;

  switch (type) {
    case 'input_audio_buffer.speech_started':
      // User started speaking
      const currentState = get(voiceStore).state;

      if (currentState === 'speaking') {
        // Barge-in detected! Stop TTS
        this.onBargeIn?.();
      }

      voiceStore.setState('listening');
      break;

    // ... rest of cases ...
  }
}

// Callback for barge-in
onBargeIn: (() => void) | null = null;
```

Wire up in ChatInput:

```typescript
realtimeClient.onBargeIn = () => {
  ttsPlayer.stop();
};
```

#### 4.3 Add Tool Execution Feedback

**File**: `/frontend/src/lib/components/chat/ChatWindow.svelte`

Add voice feedback during tool execution:

```typescript
// When tool starts
onToolCall: (event) => {
  chatStore.addToolCall(assistantMessageId, {
    id: event.id,
    name: event.name,
    parameters: event.parameters,
    status: 'running',
    result: null
  });

  // If in voice mode, speak tool name
  if (get(voiceStore).isActive) {
    const toolNameSpoken = getToolDisplayName(event.name);
    const ttsPlayer = new TTSPlayer();
    ttsPlayer.play(`${toolNameSpoken}...`);
  }
},
```

Add "thinking" sound for longer waits (optional enhancement):

```typescript
// Play subtle thinking sound when processing takes > 2 seconds
let thinkingSound: HTMLAudioElement | null = null;

const thinkingTimeout = setTimeout(() => {
  if (get(voiceStore).state === 'processing') {
    thinkingSound = new Audio('/sounds/thinking.mp3');
    thinkingSound.loop = true;
    thinkingSound.volume = 0.3;
    thinkingSound.play();
  }
}, 2000);

// Stop thinking sound when response arrives
if (thinkingSound) {
  thinkingSound.pause();
  thinkingSound = null;
}
```

---

### Phase 5: Error Handling & Fallbacks (1-2 hours)

#### 5.1 WebRTC Availability Check

**File**: `/frontend/src/lib/services/realtime-client.ts`

Add capability detection:

```typescript
static isSupported(): boolean {
  return !!(
    navigator.mediaDevices &&
    navigator.mediaDevices.getUserMedia &&
    window.RTCPeerConnection
  );
}
```

Use in ChatInput:

```typescript
$: voiceAvailable = RealtimeClient.isSupported();

<VoiceButton
  onToggle={toggleVoice}
  disabled={disabled || !voiceAvailable}
/>

{#if !voiceAvailable}
  <div class="voice-unavailable">
    Voice chat requires a modern browser with microphone support
  </div>
{/if}
```

#### 5.2 Error Spoken Aloud

**File**: `/frontend/src/lib/stores/chat.ts`

When tool error occurs:

```typescript
onToolResult: (event) => {
  // ... existing code ...

  if (!event.result.success && get(voiceStore).isActive) {
    const errorMessage = event.result.error || 'An error occurred';
    const ttsPlayer = new TTSPlayer();
    ttsPlayer.play(`Error: ${errorMessage}`);
  }
},
```

#### 5.3 Connection Loss Handling

**File**: `/frontend/src/lib/services/realtime-client.ts`

Handle disconnection:

```typescript
this.peerConnection.onconnectionstatechange = () => {
  const state = this.peerConnection?.connectionState;

  if (state === 'failed' || state === 'disconnected') {
    voiceStore.setError('Connection lost. Switching to text mode.');
    this.disconnect();
  }
};
```

---

### Phase 6: Audio Assets & Polish (1-2 hours)

#### 6.1 Create Thinking Sound

Create subtle ambient "thinking" sound (or use royalty-free):
- Low volume white noise or soft beep
- Non-intrusive
- Loops seamlessly

**File**: `/frontend/static/sounds/thinking.mp3`

#### 6.2 Safari Audio Unlock

**File**: `/frontend/src/lib/services/tts-player.ts`

Add audio context unlock on first interaction:

```typescript
class TTSPlayer {
  private static audioUnlocked = false;

  static async unlockAudio(): Promise<void> {
    if (this.audioUnlocked) return;

    try {
      const audioContext = new AudioContext();
      const buffer = audioContext.createBuffer(1, 1, 22050);
      const source = audioContext.createBufferSource();
      source.buffer = buffer;
      source.connect(audioContext.destination);
      source.start();

      this.audioUnlocked = true;
    } catch (error) {
      console.warn('Audio unlock failed:', error);
    }
  }

  // ... rest of class ...
}
```

Call on first voice button click:

```typescript
async function toggleVoice() {
  // Unlock audio on Safari
  await TTSPlayer.unlockAudio();

  // ... rest of toggle logic ...
}
```

#### 6.3 Visual Polish

Add state-dependent styling:

```css
/* Listening state - pulsing mic */
.voice-button.listening {
  animation: pulse 2s ease-in-out infinite;
}

/* Processing state - spinning */
.voice-button.processing {
  animation: spin 1s linear infinite;
}

/* Speaking state - subtle glow */
.voice-button.speaking {
  box-shadow: 0 0 0 3px rgba(var(--color-primary-rgb), 0.3);
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.6; }
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
```

---

## File Structure Summary

### Backend Files

**New files:**
```
backend/
├── api/
│   ├── routers/
│   │   └── voice.py                    # Voice endpoints
│   └── services/
│       └── voice_session_service.py     # Session management
```

**Modified files:**
```
backend/
├── api/
│   ├── config.py                        # Add OpenAI config
│   └── main.py                          # Register voice router
└── requirements.txt                     # Add httpx
```

### Frontend Files

**New files:**
```
frontend/
├── src/
│   └── lib/
│       ├── components/
│       │   └── chat/
│       │       ├── VoiceButton.svelte
│       │       └── VoiceTranscript.svelte
│       ├── services/
│       │   ├── realtime-client.ts
│       │   └── tts-player.ts
│       └── stores/
│           └── voice.ts
└── static/
    └── sounds/
        └── thinking.mp3                 # Thinking sound
```

**Modified files:**
```
frontend/
└── src/
    └── lib/
        ├── components/
        │   └── chat/
        │       ├── ChatInput.svelte     # Add voice button
        │       └── ChatWindow.svelte    # Add tool feedback
        └── stores/
            └── chat.ts                  # Add voice response handling
```

---

## Testing Checklist

### Backend Testing

- [ ] `/api/voice/session` returns valid ephemeral token
- [ ] Token expires after 15 minutes
- [ ] `/api/voice/tts` streams audio correctly
- [ ] TTS handles various text lengths (short, medium, long)
- [ ] TTS handles special characters and emojis
- [ ] Error handling for OpenAI API failures
- [ ] Rate limiting works (if implemented)

### Frontend Testing - Chrome

- [ ] Microphone permission prompt appears
- [ ] WebRTC connection establishes successfully
- [ ] Real-time transcript appears while speaking
- [ ] Transcript sent to Claude when user stops speaking
- [ ] Claude response plays as audio
- [ ] Tool execution speaks tool names
- [ ] Errors are spoken aloud
- [ ] Barge-in stops current audio
- [ ] Voice/text switching preserves conversation
- [ ] Toggle button shows correct state

### Frontend Testing - Safari

- [ ] All Chrome tests pass
- [ ] Audio plays correctly (after unlock)
- [ ] No audio playback errors
- [ ] WebRTC works on iOS Safari (if mobile tested)

### Edge Cases

- [ ] Network loss during voice session
- [ ] OpenAI Realtime timeout
- [ ] Multiple rapid voice inputs
- [ ] Very long voice input (>30 seconds)
- [ ] Empty/silent audio input
- [ ] Background noise handling
- [ ] Simultaneous text and voice input
- [ ] Switching conversations while in voice mode

---

## Success Criteria

- ✅ User can toggle voice mode with one click
- ✅ Real-time transcript appears while speaking
- ✅ Transcripts appear in chat history alongside text
- ✅ Claude responses are spoken aloud in voice mode
- ✅ Tool execution provides verbal feedback
- ✅ Barge-in stops playback and starts listening
- ✅ Voice and text share same conversation context
- ✅ Graceful fallback to text if WebRTC unavailable
- ✅ Works in Chrome and Safari (desktop)
- ✅ No audio storage (privacy preserved)
- ✅ Ephemeral tokens expire and refresh correctly

---

## Estimated Timeline

| Phase | Task | Time Estimate |
|-------|------|---------------|
| 1 | Backend - Session & TTS | 2-3 hours |
| 2 | Frontend - WebRTC | 3-4 hours |
| 3 | Frontend - Voice UI | 3-4 hours |
| 4 | Voice/Text Integration | 2-3 hours |
| 5 | Error Handling | 1-2 hours |
| 6 | Polish & Assets | 1-2 hours |

**Total: 12-18 hours**

**Recommended approach:** Build phases sequentially, testing each phase before moving to the next.

---

## Cost Estimates

### Per Conversation (Average)

Assumptions:
- 5-minute conversation
- User speaks 3 times (30 seconds each)
- Claude responds 3 times (~200 words each)

**Costs:**
- STT (Realtime): 1.5 min × $0.06/min = $0.09
- TTS: 600 words × $0.015/1K chars = $0.01
- **Total: ~$0.10 per 5-min conversation**

Plus Claude API costs (existing).

### Monthly (100 users, 2 conversations/day each)

- 100 users × 2 conversations × 30 days = 6,000 conversations
- 6,000 × $0.10 = **$600/month**

Manageable for a SaaS product with paying users.

---

## Future Enhancements (Post-v1)

### Phase 2 Features
- **Voice selection UI** - Let users choose TTS voice
- **Mobile support** - iOS/Android optimization
- **Multi-language** - Support non-English languages
- **Voice settings** - Speed, pitch adjustments
- **Audio storage** - Optional recording/playback
- **Voice-only mode** - Hands-free continuous conversation
- **Better thinking sounds** - More pleasant ambient audio
- **Waveform visualization** - Audio level display
- **Push-to-talk mode** - Alternative to toggle
- **Keyboard shortcuts** - Quick voice activation

### Advanced Features
- **Voice activity detection tuning** - Adjust sensitivity
- **Custom wake words** - "Hey Claude" activation
- **Voice commands** - "Create note", "Search for..."
- **Conversation summaries** - Auto-generate from voice
- **Voice analytics** - Usage metrics and insights

---

## Security & Privacy Notes

### Data Flow
- ✅ Audio streamed to OpenAI (HTTPS/WebRTC)
- ✅ Transcripts stored in DB (like text messages)
- ✅ No audio recordings stored
- ✅ Ephemeral tokens expire (no long-lived credentials)

### Privacy Considerations
- Users should be informed audio is processed by OpenAI
- Consider adding privacy notice on first voice use
- GDPR compliance: transcripts are user data (same as text)
- No third-party analytics on voice data

### Security Best Practices
- ✅ Ephemeral tokens (not API keys) in browser
- ✅ Short token lifetime (15 minutes)
- ✅ Backend validates all requests
- ✅ CORS properly configured
- ✅ Content-Security-Policy allows audio playback

---

## Resources

### Documentation
- [OpenAI Realtime API](https://platform.openai.com/docs/guides/realtime)
- [OpenAI TTS API](https://platform.openai.com/docs/guides/text-to-speech)
- [WebRTC MDN](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API)

### Example Code
- [OpenAI Realtime Console](https://github.com/openai/openai-realtime-console)

### Browser Compatibility
- Chrome: ✅ Full support
- Safari: ✅ Full support (with audio unlock)
- Firefox: ✅ WebRTC support (may need testing)
- Edge: ✅ Chromium-based, full support
