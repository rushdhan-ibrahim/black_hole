/**
 * Gargantua - WebGL Renderer Module
 * Handles shader compilation, WebGL context, camera controls, and render loop
 */

export class GargantuaRenderer {
    constructor(canvas) {
        this.canvas = canvas;
        this.gl = null;
        this.program = null;
        this.uniforms = {};
        this.settings = {
            doppler: true,
            redshift: true
        };
        this.frameCount = 0;
        this.lastFpsTime = performance.now();
        this.onFpsUpdate = null;

        // Camera state
        this.camera = {
            azimuth: Math.PI,         // Start looking from -Z direction
            elevation: 0.17,          // Slight angle above disk (~10 degrees)
            distance: 35.0,
            zoom: 1.8,
            // Smooth interpolation targets
            targetAzimuth: Math.PI,
            targetElevation: 0.17,
            targetDistance: 35.0,
            targetZoom: 1.8
        };

        // Mouse state
        this.mouse = {
            isDown: false,
            lastX: 0,
            lastY: 0,
            button: 0
        };

        // Touch state
        this.touch = {
            lastDist: 0,
            lastX: 0,
            lastY: 0
        };
    }

    async init() {
        this.gl = this.canvas.getContext('webgl', {
            alpha: false,
            antialias: false,
            depth: false,
            preserveDrawingBuffer: false,
            powerPreference: 'high-performance'
        });

        if (!this.gl) {
            throw new Error('WebGL not supported');
        }

        await this.loadShaders();
        this.setupGeometry();
        this.setupUniforms();
        this.setupControls();
        this.resize();

        window.addEventListener('resize', () => this.resize());
    }

    async loadShaders() {
        const [vertexSrc, fragmentSrc] = await Promise.all([
            fetch('src/shaders/vertex.glsl').then(r => r.text()),
            fetch('src/shaders/fragment.glsl').then(r => r.text())
        ]);

        const vertShader = this.compileShader(this.gl.VERTEX_SHADER, vertexSrc);
        const fragShader = this.compileShader(this.gl.FRAGMENT_SHADER, fragmentSrc);

        this.program = this.gl.createProgram();
        this.gl.attachShader(this.program, vertShader);
        this.gl.attachShader(this.program, fragShader);
        this.gl.linkProgram(this.program);

        if (!this.gl.getProgramParameter(this.program, this.gl.LINK_STATUS)) {
            throw new Error('Shader program link failed: ' + this.gl.getProgramInfoLog(this.program));
        }

        this.gl.useProgram(this.program);
    }

    compileShader(type, source) {
        const shader = this.gl.createShader(type);
        this.gl.shaderSource(shader, source);
        this.gl.compileShader(shader);

        if (!this.gl.getShaderParameter(shader, this.gl.COMPILE_STATUS)) {
            const info = this.gl.getShaderInfoLog(shader);
            throw new Error('Shader compilation failed: ' + info);
        }

        return shader;
    }

    setupGeometry() {
        const buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, buffer);
        this.gl.bufferData(
            this.gl.ARRAY_BUFFER,
            new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
            this.gl.STATIC_DRAW
        );

        const posLoc = this.gl.getAttribLocation(this.program, 'position');
        this.gl.enableVertexAttribArray(posLoc);
        this.gl.vertexAttribPointer(posLoc, 2, this.gl.FLOAT, false, 0, 0);
    }

    setupUniforms() {
        this.uniforms = {
            resolution: this.gl.getUniformLocation(this.program, 'uResolution'),
            time: this.gl.getUniformLocation(this.program, 'uTime'),
            doppler: this.gl.getUniformLocation(this.program, 'uDoppler'),
            redshift: this.gl.getUniformLocation(this.program, 'uRedshift'),
            // Camera uniforms
            camAzimuth: this.gl.getUniformLocation(this.program, 'uCamAzimuth'),
            camElevation: this.gl.getUniformLocation(this.program, 'uCamElevation'),
            camDistance: this.gl.getUniformLocation(this.program, 'uCamDistance'),
            camZoom: this.gl.getUniformLocation(this.program, 'uCamZoom')
        };
    }

    setupControls() {
        // Mouse controls
        this.canvas.addEventListener('mousedown', (e) => this.onMouseDown(e));
        window.addEventListener('mousemove', (e) => this.onMouseMove(e));
        window.addEventListener('mouseup', (e) => this.onMouseUp(e));
        this.canvas.addEventListener('wheel', (e) => this.onWheel(e), { passive: false });

        // Touch controls
        this.canvas.addEventListener('touchstart', (e) => this.onTouchStart(e), { passive: false });
        this.canvas.addEventListener('touchmove', (e) => this.onTouchMove(e), { passive: false });
        this.canvas.addEventListener('touchend', (e) => this.onTouchEnd(e));

        // Prevent context menu on right-click
        this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());

        // Hide hint after first interaction
        this.canvas.addEventListener('mousedown', () => this.hideHint(), { once: true });
        this.canvas.addEventListener('touchstart', () => this.hideHint(), { once: true });
    }

    hideHint() {
        const hint = document.querySelector('.camera-hint');
        if (hint) hint.classList.add('hidden');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MOUSE CONTROLS
    // ═══════════════════════════════════════════════════════════════════════════

    onMouseDown(e) {
        this.mouse.isDown = true;
        this.mouse.button = e.button;
        this.mouse.lastX = e.clientX;
        this.mouse.lastY = e.clientY;
    }

    onMouseMove(e) {
        if (!this.mouse.isDown) return;

        const dx = e.clientX - this.mouse.lastX;
        const dy = e.clientY - this.mouse.lastY;

        if (this.mouse.button === 0) {
            // Left button: orbit
            this.camera.targetAzimuth -= dx * 0.005;
            this.camera.targetElevation += dy * 0.005;

            // Clamp elevation to avoid flipping
            this.camera.targetElevation = Math.max(-Math.PI * 0.45, Math.min(Math.PI * 0.45, this.camera.targetElevation));
        } else if (this.mouse.button === 2) {
            // Right button: zoom (vertical drag)
            this.camera.targetDistance *= 1.0 + dy * 0.005;
            this.camera.targetDistance = Math.max(10, Math.min(100, this.camera.targetDistance));
        }

        this.mouse.lastX = e.clientX;
        this.mouse.lastY = e.clientY;
    }

    onMouseUp(e) {
        this.mouse.isDown = false;
    }

    onWheel(e) {
        e.preventDefault();

        // Zoom with scroll wheel
        const delta = e.deltaY > 0 ? 1.1 : 0.9;
        this.camera.targetDistance *= delta;
        this.camera.targetDistance = Math.max(10, Math.min(100, this.camera.targetDistance));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOUCH CONTROLS
    // ═══════════════════════════════════════════════════════════════════════════

    onTouchStart(e) {
        e.preventDefault();

        if (e.touches.length === 1) {
            this.touch.lastX = e.touches[0].clientX;
            this.touch.lastY = e.touches[0].clientY;
        } else if (e.touches.length === 2) {
            // Pinch zoom
            const dx = e.touches[0].clientX - e.touches[1].clientX;
            const dy = e.touches[0].clientY - e.touches[1].clientY;
            this.touch.lastDist = Math.sqrt(dx * dx + dy * dy);
        }
    }

    onTouchMove(e) {
        e.preventDefault();

        if (e.touches.length === 1) {
            // Single finger: orbit
            const dx = e.touches[0].clientX - this.touch.lastX;
            const dy = e.touches[0].clientY - this.touch.lastY;

            this.camera.targetAzimuth -= dx * 0.005;
            this.camera.targetElevation += dy * 0.005;
            this.camera.targetElevation = Math.max(-Math.PI * 0.45, Math.min(Math.PI * 0.45, this.camera.targetElevation));

            this.touch.lastX = e.touches[0].clientX;
            this.touch.lastY = e.touches[0].clientY;
        } else if (e.touches.length === 2) {
            // Pinch: zoom
            const dx = e.touches[0].clientX - e.touches[1].clientX;
            const dy = e.touches[0].clientY - e.touches[1].clientY;
            const dist = Math.sqrt(dx * dx + dy * dy);

            if (this.touch.lastDist > 0) {
                const scale = this.touch.lastDist / dist;
                this.camera.targetDistance *= scale;
                this.camera.targetDistance = Math.max(10, Math.min(100, this.camera.targetDistance));
            }

            this.touch.lastDist = dist;
        }
    }

    onTouchEnd(e) {
        this.touch.lastDist = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAMERA UPDATE
    // ═══════════════════════════════════════════════════════════════════════════

    updateCamera() {
        // Smooth interpolation toward targets
        const smoothing = 0.15;

        this.camera.azimuth += (this.camera.targetAzimuth - this.camera.azimuth) * smoothing;
        this.camera.elevation += (this.camera.targetElevation - this.camera.elevation) * smoothing;
        this.camera.distance += (this.camera.targetDistance - this.camera.distance) * smoothing;
        this.camera.zoom += (this.camera.targetZoom - this.camera.zoom) * smoothing;
    }

    resize() {
        // Resolution scale for performance (0.85 = 85% resolution)
        const resolutionScale = 0.85;
        const dpr = Math.min(window.devicePixelRatio, 1.0) * resolutionScale;
        this.canvas.width = Math.floor(window.innerWidth * dpr);
        this.canvas.height = Math.floor(window.innerHeight * dpr);
        this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    }

    toggleSetting(key) {
        if (key in this.settings) {
            this.settings[key] = !this.settings[key];
            return this.settings[key];
        }
        return null;
    }

    render(timestamp) {
        // FPS calculation
        this.frameCount++;
        if (timestamp - this.lastFpsTime > 1000) {
            if (this.onFpsUpdate) {
                this.onFpsUpdate(this.frameCount);
            }
            this.frameCount = 0;
            this.lastFpsTime = timestamp;
        }

        // Update camera smoothing
        this.updateCamera();

        // Update uniforms
        this.gl.uniform2f(this.uniforms.resolution, this.canvas.width, this.canvas.height);
        this.gl.uniform1f(this.uniforms.time, timestamp * 0.001);
        this.gl.uniform1f(this.uniforms.doppler, this.settings.doppler ? 1.0 : 0.0);
        this.gl.uniform1f(this.uniforms.redshift, this.settings.redshift ? 1.0 : 0.0);

        // Camera uniforms
        this.gl.uniform1f(this.uniforms.camAzimuth, this.camera.azimuth);
        this.gl.uniform1f(this.uniforms.camElevation, this.camera.elevation);
        this.gl.uniform1f(this.uniforms.camDistance, this.camera.distance);
        this.gl.uniform1f(this.uniforms.camZoom, this.camera.zoom);

        // Draw
        this.gl.drawArrays(this.gl.TRIANGLES, 0, 6);
    }

    startLoop() {
        const loop = (timestamp) => {
            this.render(timestamp);
            requestAnimationFrame(loop);
        };
        requestAnimationFrame(loop);
    }
}
