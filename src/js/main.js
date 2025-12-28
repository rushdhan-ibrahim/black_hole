/**
 * Gargantua - Main Application Entry Point
 */

import { GargantuaRenderer } from './renderer.js';
import { GargantuaAudio } from './audio.js';

document.addEventListener('DOMContentLoaded', async () => {
    const canvas = document.getElementById('glcanvas');
    const fpsEl = document.getElementById('fps');

    try {
        const renderer = new GargantuaRenderer(canvas);
        await renderer.init();

        // Initialize audio system
        const audio = new GargantuaAudio();
        await audio.init();

        // FPS display callback
        renderer.onFpsUpdate = (fps) => {
            fpsEl.textContent = fps + ' fps';
        };

        // Connect camera distance to audio modulation
        renderer.onDistanceUpdate = (distance) => {
            audio.updateDistance(distance);
        };

        // Setup button controls
        setupButton('doppler', 'doppler', renderer);
        setupButton('redshift', 'redshift', renderer);
        setupAudioButton('sound', audio);

        // Start render loop
        renderer.startLoop();

        console.log('Gargantua initialized successfully');
    } catch (error) {
        console.error('Initialization failed:', error);
        document.body.innerHTML = `<div style="color:#fa8;padding:40px">Error: ${error.message}</div>`;
    }
});

function setupButton(elementId, settingKey, renderer) {
    const btn = document.getElementById(elementId);
    if (btn) {
        btn.onclick = () => {
            const newState = renderer.toggleSetting(settingKey);
            btn.classList.toggle('on', newState);
        };
    }
}

function setupAudioButton(elementId, audio) {
    const btn = document.getElementById(elementId);
    if (btn) {
        btn.onclick = () => {
            const isPlaying = audio.toggle();
            btn.classList.toggle('on', isPlaying);
        };
    }
}
