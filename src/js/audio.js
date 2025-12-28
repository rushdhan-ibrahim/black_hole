/**
 * Gargantua - Immersive Audio Soundscape
 *
 * A procedurally generated soundscape evoking the cosmic majesty
 * and terrifying beauty of a supermassive black hole.
 */

export class GargantuaAudio {
    constructor() {
        this.ctx = null;
        this.masterGain = null;
        this.isPlaying = false;
        this.nodes = {};

        // Fade duration for smooth transitions
        this.fadeDuration = 2.0;

        // Distance-based modulation
        this.distanceFilter = null;
        this.currentDistance = 35.0;
        this.minDistance = 20.0;
        this.maxDistance = 80.0;
    }

    async init() {
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();

        // Master output with compression for smooth dynamics
        this.masterGain = this.ctx.createGain();
        this.masterGain.gain.value = 0;

        // Distance-based low-pass filter (closer = more bass)
        this.distanceFilter = this.ctx.createBiquadFilter();
        this.distanceFilter.type = 'lowpass';
        this.distanceFilter.frequency.value = 2000;
        this.distanceFilter.Q.value = 0.7;

        // Bass boost filter for proximity effect
        this.proximityBass = this.ctx.createBiquadFilter();
        this.proximityBass.type = 'lowshelf';
        this.proximityBass.frequency.value = 150;
        this.proximityBass.gain.value = 0;

        const compressor = this.ctx.createDynamicsCompressor();
        compressor.threshold.value = -24;
        compressor.knee.value = 30;
        compressor.ratio.value = 4;
        compressor.attack.value = 0.003;
        compressor.release.value = 0.25;

        // Chain: masterGain -> distanceFilter -> proximityBass -> compressor -> output
        this.masterGain.connect(this.distanceFilter);
        this.distanceFilter.connect(this.proximityBass);
        this.proximityBass.connect(compressor);
        compressor.connect(this.ctx.destination);

        // Create all sound layers
        this.createGravitationalDrone();
        this.createAccretionFlow();
        this.createPhotonShimmer();
        this.createTimePulse();
        this.createCosmicVoid();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 1: GRAVITATIONAL RUMBLE - Deep, smooth cosmic presence
    // ═══════════════════════════════════════════════════════════════════════════

    createGravitationalDrone() {
        const gain = this.ctx.createGain();
        gain.gain.value = 0.15;  // Lower volume, more subtle
        gain.connect(this.masterGain);

        // Deep sub-bass foundation (28 Hz - felt in the chest)
        const subBass = this.ctx.createOscillator();
        subBass.type = 'sine';
        subBass.frequency.value = 28;

        // Warm low tone (55 Hz - A1, musical foundation)
        const lowTone = this.ctx.createOscillator();
        lowTone.type = 'sine';
        lowTone.frequency.value = 55;

        // Very slow pitch drift for organic movement (no buzzy beating)
        const driftLfo = this.ctx.createOscillator();
        driftLfo.type = 'sine';
        driftLfo.frequency.value = 0.03;  // 33 second cycle

        const driftGain = this.ctx.createGain();
        driftGain.gain.value = 1.5;  // Subtle pitch wobble

        driftLfo.connect(driftGain);
        driftGain.connect(lowTone.frequency);

        // Individual gains for mixing
        const subGain = this.ctx.createGain();
        subGain.gain.value = 0.4;

        const lowGain = this.ctx.createGain();
        lowGain.gain.value = 0.3;

        // Gentle low-pass for smoothness
        const lpf = this.ctx.createBiquadFilter();
        lpf.type = 'lowpass';
        lpf.frequency.value = 80;
        lpf.Q.value = 0.5;

        // Connect
        subBass.connect(subGain);
        lowTone.connect(lowGain);

        subGain.connect(lpf);
        lowGain.connect(lpf);
        lpf.connect(gain);

        // Very slow breathing (40 second cycle)
        const breathLfo = this.ctx.createOscillator();
        breathLfo.type = 'sine';
        breathLfo.frequency.value = 0.025;

        const breathGain = this.ctx.createGain();
        breathGain.gain.value = 0.04;

        breathLfo.connect(breathGain);
        breathGain.connect(gain.gain);

        this.nodes.drone = {
            oscillators: [subBass, lowTone, driftLfo, breathLfo],
            gain
        };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 2: ACCRETION FLOW - Swirling cosmic wind
    // ═══════════════════════════════════════════════════════════════════════════

    createAccretionFlow() {
        const gain = this.ctx.createGain();
        gain.gain.value = 0.12;
        gain.connect(this.masterGain);

        // Create noise source using buffer
        const bufferSize = this.ctx.sampleRate * 2;
        const noiseBuffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
        const data = noiseBuffer.getChannelData(0);

        // Pink-ish noise (more natural than white noise)
        let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
        for (let i = 0; i < bufferSize; i++) {
            const white = Math.random() * 2 - 1;
            b0 = 0.99886 * b0 + white * 0.0555179;
            b1 = 0.99332 * b1 + white * 0.0750759;
            b2 = 0.96900 * b2 + white * 0.1538520;
            b3 = 0.86650 * b3 + white * 0.3104856;
            b4 = 0.55000 * b4 + white * 0.5329522;
            b5 = -0.7616 * b5 - white * 0.0168980;
            data[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
            b6 = white * 0.115926;
        }

        const noise = this.ctx.createBufferSource();
        noise.buffer = noiseBuffer;
        noise.loop = true;

        // Band-pass filter for that whooshing quality
        const bpf = this.ctx.createBiquadFilter();
        bpf.type = 'bandpass';
        bpf.frequency.value = 200;
        bpf.Q.value = 0.8;

        // LFO to sweep the filter frequency (swirling effect)
        const filterLfo = this.ctx.createOscillator();
        filterLfo.type = 'sine';
        filterLfo.frequency.value = 0.08; // Slow sweep

        const filterLfoGain = this.ctx.createGain();
        filterLfoGain.gain.value = 150; // Sweep range

        filterLfo.connect(filterLfoGain);
        filterLfoGain.connect(bpf.frequency);

        // Second filter sweep at different rate for complexity
        const filterLfo2 = this.ctx.createOscillator();
        filterLfo2.type = 'sine';
        filterLfo2.frequency.value = 0.03;

        const filterLfo2Gain = this.ctx.createGain();
        filterLfo2Gain.gain.value = 80;

        filterLfo2.connect(filterLfo2Gain);
        filterLfo2Gain.connect(bpf.frequency);

        // Volume modulation for organic movement
        const volLfo = this.ctx.createOscillator();
        volLfo.type = 'sine';
        volLfo.frequency.value = 0.12;

        const volLfoGain = this.ctx.createGain();
        volLfoGain.gain.value = 0.04;

        volLfo.connect(volLfoGain);
        volLfoGain.connect(gain.gain);

        noise.connect(bpf);
        bpf.connect(gain);

        this.nodes.flow = {
            source: noise,
            oscillators: [filterLfo, filterLfo2, volLfo],
            gain
        };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 3: PHOTON SHIMMER - Ethereal ring harmonics
    // ═══════════════════════════════════════════════════════════════════════════

    createPhotonShimmer() {
        const gain = this.ctx.createGain();
        gain.gain.value = 0.06;
        gain.connect(this.masterGain);

        // High, ethereal tones (harmonics of light orbiting the black hole)
        const frequencies = [880, 1320, 1760, 2640]; // A5 and harmonics
        const oscillators = [];
        const gains = [];

        frequencies.forEach((freq, i) => {
            const osc = this.ctx.createOscillator();
            osc.type = 'sine';
            osc.frequency.value = freq;

            const oscGain = this.ctx.createGain();
            oscGain.gain.value = 0.15 / (i + 1); // Higher harmonics are quieter

            // Subtle vibrato for each
            const vibrato = this.ctx.createOscillator();
            vibrato.type = 'sine';
            vibrato.frequency.value = 0.5 + i * 0.2;

            const vibratoGain = this.ctx.createGain();
            vibratoGain.gain.value = freq * 0.003; // Subtle pitch wobble

            vibrato.connect(vibratoGain);
            vibratoGain.connect(osc.frequency);

            osc.connect(oscGain);
            oscGain.connect(gain);

            oscillators.push(osc, vibrato);
            gains.push(oscGain);
        });

        // Amplitude modulation for shimmering effect
        const shimmerLfo = this.ctx.createOscillator();
        shimmerLfo.type = 'sine';
        shimmerLfo.frequency.value = 0.3;

        const shimmerGain = this.ctx.createGain();
        shimmerGain.gain.value = 0.03;

        shimmerLfo.connect(shimmerGain);
        shimmerGain.connect(gain.gain);

        oscillators.push(shimmerLfo);

        // High-pass to keep it airy
        const hpf = this.ctx.createBiquadFilter();
        hpf.type = 'highpass';
        hpf.frequency.value = 600;
        hpf.Q.value = 0.5;

        // Reconnect through filter
        gain.disconnect();
        gain.connect(hpf);
        hpf.connect(this.masterGain);

        this.nodes.shimmer = { oscillators, gain };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 4: TIME PULSE - The slowing of time near the horizon
    // ═══════════════════════════════════════════════════════════════════════════

    createTimePulse() {
        const gain = this.ctx.createGain();
        gain.gain.value = 0.08;
        gain.connect(this.masterGain);

        // Deep, resonant tick - like a cosmic clock slowing down
        const tick = this.ctx.createOscillator();
        tick.type = 'sine';
        tick.frequency.value = 80;

        // Envelope for the tick
        const tickEnv = this.ctx.createGain();
        tickEnv.gain.value = 0;

        // Filter for warmth
        const tickFilter = this.ctx.createBiquadFilter();
        tickFilter.type = 'lowpass';
        tickFilter.frequency.value = 200;
        tickFilter.Q.value = 2;

        tick.connect(tickEnv);
        tickEnv.connect(tickFilter);
        tickFilter.connect(gain);

        // Schedule the pulse pattern
        const pulseInterval = 2.5; // Slow, hypnotic rhythm

        const schedulePulse = () => {
            if (!this.isPlaying) return;

            const now = this.ctx.currentTime;

            // Quick attack, slow decay
            tickEnv.gain.cancelScheduledValues(now);
            tickEnv.gain.setValueAtTime(0, now);
            tickEnv.gain.linearRampToValueAtTime(1, now + 0.02);
            tickEnv.gain.exponentialRampToValueAtTime(0.001, now + 1.5);

            // Slight pitch drop during decay (time dilation effect)
            tick.frequency.cancelScheduledValues(now);
            tick.frequency.setValueAtTime(80, now);
            tick.frequency.exponentialRampToValueAtTime(40, now + 1.5);

            setTimeout(schedulePulse, pulseInterval * 1000);
        };

        this.nodes.pulse = {
            oscillators: [tick],
            gain,
            start: schedulePulse
        };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5: COSMIC VOID - The vast emptiness of space
    // ═══════════════════════════════════════════════════════════════════════════

    createCosmicVoid() {
        const gain = this.ctx.createGain();
        gain.gain.value = 0.05;
        gain.connect(this.masterGain);

        // Very low, evolving pad
        const pad1 = this.ctx.createOscillator();
        pad1.type = 'sine';
        pad1.frequency.value = 55; // A1

        const pad2 = this.ctx.createOscillator();
        pad2.type = 'sine';
        pad2.frequency.value = 82.5; // E2 (perfect fifth)

        const pad3 = this.ctx.createOscillator();
        pad3.type = 'triangle';
        pad3.frequency.value = 110; // A2 (octave)

        // Very slow detuning for movement
        const detuneLfo = this.ctx.createOscillator();
        detuneLfo.type = 'sine';
        detuneLfo.frequency.value = 0.02; // 50 second cycle

        const detuneGain = this.ctx.createGain();
        detuneGain.gain.value = 2; // Subtle detuning in Hz

        detuneLfo.connect(detuneGain);
        detuneGain.connect(pad2.frequency);

        // Low-pass for smoothness
        const lpf = this.ctx.createBiquadFilter();
        lpf.type = 'lowpass';
        lpf.frequency.value = 300;
        lpf.Q.value = 0.5;

        const padGain = this.ctx.createGain();
        padGain.gain.value = 0.3;

        pad1.connect(padGain);
        pad2.connect(padGain);
        pad3.connect(padGain);
        padGain.connect(lpf);
        lpf.connect(gain);

        // Slow volume swell
        const swellLfo = this.ctx.createOscillator();
        swellLfo.type = 'sine';
        swellLfo.frequency.value = 0.015;

        const swellGain = this.ctx.createGain();
        swellGain.gain.value = 0.025;

        swellLfo.connect(swellGain);
        swellGain.connect(gain.gain);

        this.nodes.void = {
            oscillators: [pad1, pad2, pad3, detuneLfo, swellLfo],
            gain
        };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PLAYBACK CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    async start() {
        if (this.isPlaying) return;

        // Resume context if suspended (browser autoplay policy)
        if (this.ctx.state === 'suspended') {
            await this.ctx.resume();
        }

        this.isPlaying = true;

        // Start all oscillators
        const now = this.ctx.currentTime;

        this.nodes.drone.oscillators.forEach(osc => osc.start(now));
        this.nodes.flow.source.start(now);
        this.nodes.flow.oscillators.forEach(osc => osc.start(now));
        this.nodes.shimmer.oscillators.forEach(osc => osc.start(now));
        this.nodes.pulse.oscillators.forEach(osc => osc.start(now));
        this.nodes.void.oscillators.forEach(osc => osc.start(now));

        // Start the time pulse scheduling
        this.nodes.pulse.start();

        // Fade in
        this.masterGain.gain.cancelScheduledValues(now);
        this.masterGain.gain.setValueAtTime(0, now);
        this.masterGain.gain.linearRampToValueAtTime(0.7, now + this.fadeDuration);
    }

    stop() {
        if (!this.isPlaying) return;

        const now = this.ctx.currentTime;

        // Fade out
        this.masterGain.gain.cancelScheduledValues(now);
        this.masterGain.gain.setValueAtTime(this.masterGain.gain.value, now);
        this.masterGain.gain.linearRampToValueAtTime(0, now + this.fadeDuration);

        // Stop after fade
        setTimeout(() => {
            this.isPlaying = false;

            // Stop and disconnect all nodes
            try {
                this.nodes.drone.oscillators.forEach(osc => osc.stop());
                this.nodes.flow.source.stop();
                this.nodes.flow.oscillators.forEach(osc => osc.stop());
                this.nodes.shimmer.oscillators.forEach(osc => osc.stop());
                this.nodes.pulse.oscillators.forEach(osc => osc.stop());
                this.nodes.void.oscillators.forEach(osc => osc.stop());
            } catch (e) {
                // Oscillators already stopped
            }

            // Reinitialize for next play
            this.nodes = {};
            this.createGravitationalDrone();
            this.createAccretionFlow();
            this.createPhotonShimmer();
            this.createTimePulse();
            this.createCosmicVoid();

        }, this.fadeDuration * 1000 + 100);
    }

    toggle() {
        if (this.isPlaying) {
            this.stop();
            return false;
        } else {
            this.start();
            return true;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DISTANCE-BASED MODULATION
    // ═══════════════════════════════════════════════════════════════════════════

    updateDistance(distance) {
        if (!this.isPlaying || !this.ctx) return;

        this.currentDistance = distance;

        // Normalize distance: 0 = closest (20), 1 = farthest (80)
        const t = (distance - this.minDistance) / (this.maxDistance - this.minDistance);
        const proximity = 1.0 - Math.max(0, Math.min(1, t)); // 1 = close, 0 = far

        const now = this.ctx.currentTime;
        const smoothing = 0.3; // Smooth parameter changes

        // Volume: louder when closer (0.5 at far, 0.85 at close)
        const targetVolume = 0.5 + proximity * 0.35;
        this.masterGain.gain.setTargetAtTime(targetVolume, now, smoothing);

        // Low-pass filter: darker/more muffled when far, brighter when close
        // Far = 800 Hz, Close = 4000 Hz
        const targetLPF = 800 + proximity * 3200;
        this.distanceFilter.frequency.setTargetAtTime(targetLPF, now, smoothing);

        // Bass boost: more bass when closer (-2 dB at far, +8 dB at close)
        const targetBass = -2 + proximity * 10;
        this.proximityBass.gain.setTargetAtTime(targetBass, now, smoothing);

        // Increase drone intensity when closer
        if (this.nodes.drone && this.nodes.drone.gain) {
            const droneLevel = 0.25 + proximity * 0.2;
            this.nodes.drone.gain.gain.setTargetAtTime(droneLevel, now, smoothing);
        }

        // Increase time pulse intensity when closer
        if (this.nodes.pulse && this.nodes.pulse.gain) {
            const pulseLevel = 0.05 + proximity * 0.08;
            this.nodes.pulse.gain.gain.setTargetAtTime(pulseLevel, now, smoothing);
        }

        // Shimmer gets slightly louder and more present up close
        if (this.nodes.shimmer && this.nodes.shimmer.gain) {
            const shimmerLevel = 0.04 + proximity * 0.04;
            this.nodes.shimmer.gain.gain.setTargetAtTime(shimmerLevel, now, smoothing);
        }
    }
}
