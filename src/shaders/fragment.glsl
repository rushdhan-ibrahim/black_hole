precision highp float;

uniform vec2 uResolution;
uniform float uTime;
uniform float uDoppler;
uniform float uRedshift;

// Camera uniforms
uniform float uCamAzimuth;    // Horizontal angle (radians)
uniform float uCamElevation;  // Vertical angle (radians)
uniform float uCamDistance;   // Distance from origin
uniform float uCamZoom;       // FOV zoom factor

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

#define PI 3.14159265359

// Integration - extended range support (20-80)
#define MAX_STEPS 280
#define STEP_SIZE 0.25

// Black hole
#define M 1.0
#define RS 2.0                  // Schwarzschild radius
#define PHOTON_SPHERE 3.0       // Photon sphere at 1.5 * RS

// Accretion disk - volumetric with visible thickness
#define DISK_INNER 3.0
#define DISK_OUTER 15.0
#define DISK_H0 0.042           // Base scale height ratio (H/r)
#define DISK_FLARE 0.30         // How much disk thickens with radius
#define DISK_CUTOFF 2.5         // Sample within N scale heights (optimized)

// Camera defaults (now controlled by uniforms)
#define CAM_DIST_DEFAULT 35.0
#define CAM_ZOOM_DEFAULT 1.8

// ═══════════════════════════════════════════════════════════════════════════
// OPTIMIZED NOISE (no sin(), faster arithmetic hashes)
// ═══════════════════════════════════════════════════════════════════════════

// Fast hash - no trig, pure arithmetic
float hash(float n) {
    n = fract(n * 0.1031);
    n *= n + 33.33;
    n *= n + n;
    return fract(n);
}

float hash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

// Optimized 3D noise - inlined hash for speed
float noise(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);  // Smoothstep

    // Flatten 3D coords to 1D for hashing
    float n = p.x + p.y * 157.0 + 113.0 * p.z;

    // Inline fast hash
    #define HASH(n) fract((n) * (n) * 0.00390625 + (n) * 0.1)

    return mix(mix(mix(HASH(n), HASH(n + 1.0), f.x),
                   mix(HASH(n + 157.0), HASH(n + 158.0), f.x), f.y),
               mix(mix(HASH(n + 113.0), HASH(n + 114.0), f.x),
                   mix(HASH(n + 270.0), HASH(n + 271.0), f.x), f.y), f.z);

    #undef HASH
}

// 2-octave FBM for performance (was 3)
float fbm(vec3 p) {
    float f = 0.0;
    f += 0.50 * noise(p); p *= 2.1;
    f += 0.25 * noise(p);
    return f * 1.33;  // Normalize to ~0-1 range
}

// ═══════════════════════════════════════════════════════════════════════════
// GRAVITATIONAL PHYSICS
// ═══════════════════════════════════════════════════════════════════════════

vec3 blackHoleAccel(vec3 pos) {
    float r = length(pos);
    if (r < 0.1) return vec3(0.0);

    // Simplified GR acceleration - single division
    // Photon enhancement baked into coefficient
    float accel = 1.8 * M * RS / (r * r * r);

    return -pos * (accel / r);  // -normalize(pos) * accel, optimized
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCRETION DISK
// ═══════════════════════════════════════════════════════════════════════════

float keplerOmega(float r) {
    return sqrt(M / (r * r * r));
}

// Disk scale height - increases with radius (flaring)
float getDiskScaleHeight(float r) {
    // Normalized radius position
    float rNorm = clamp((r - DISK_INNER) / (DISK_OUTER - DISK_INNER), 0.0, 1.0);
    // Flaring: disk gets thicker at larger radii
    float flare = 1.0 + DISK_FLARE * rNorm;
    return DISK_H0 * r * flare;
}

// Gaussian vertical density profile
float verticalDensity(float y, float H) {
    float x = abs(y) / max(H, 0.001);
    return exp(-0.5 * x * x);
}

// Vertical oscillation for filament bands - creates 3D undulating motion
// Optimized: single sin call, precomputed omega passed in
float getVerticalOscillation(float phi, float r, float time, float freq, float bandIndex, float omega) {
    // Combined oscillation in single sin call
    float phase = phi * freq * 0.2 + time * omega * 2.0 + bandIndex * 2.5 - r * 0.5;
    float vOsc = sin(phase) * 0.08;  // Increased amplitude for visibility

    // Amplitude decreases with radius (inner disk more active)
    float radialFade = smoothstep(DISK_OUTER, DISK_INNER * 1.5, r);
    return vOsc * radialFade;
}

// Large-scale FBM vertical warp - creates turbulent 3D bulges and waves
// Optimized: single noise call with cheaper coordinate calculation
float getVerticalWarp(float phi, float r, float time) {
    // Simplified coordinates
    float u = r * 0.12;
    float v = phi * 0.4 + time * 0.06;

    // Single noise call
    float warp = noise(vec3(u, v, time * 0.12)) - 0.5;

    // Amplitude varies with radius - more warping in mid-disk
    float radialMod = smoothstep(DISK_INNER, DISK_INNER * 2.0, r) *
                      smoothstep(DISK_OUTER, DISK_OUTER * 0.6, r);

    return warp * 0.12 * radialMod;  // Increased amplitude for visibility
}

// Interstellar-inspired color palette
vec3 interstellarDiskColor(float temp) {
    float t = clamp(temp, 0.0, 2.0);

    // Warm orange-gold palette matching Interstellar
    vec3 outerColor = vec3(0.9, 0.35, 0.08);   // Deep orange (outer edge)
    vec3 midColor   = vec3(1.0, 0.55, 0.12);   // Warm orange
    vec3 hotColor   = vec3(1.0, 0.75, 0.3);    // Golden
    vec3 veryHot    = vec3(1.0, 0.9, 0.6);     // Warm white-gold

    vec3 col;
    if (t < 0.5) {
        col = mix(outerColor, midColor, t * 2.0);
    } else if (t < 1.0) {
        col = mix(midColor, hotColor, (t - 0.5) * 2.0);
    } else {
        col = mix(hotColor, veryHot, min(t - 1.0, 1.0));
    }

    return col;
}

// Keep original blackbody for reference/comparison (unused)
vec3 blackbody(float temp) {
    return interstellarDiskColor(temp);
}

// Sample disk - VOLUMETRIC with turbulence, flares, and chaos
vec4 sampleDiskVolumetric(vec3 p, vec3 rayDir, float time, int crossingNum, float verticalW, float stepLen) {
    float r = length(p.xz);

    // Early out - disk bounds or negligible vertical weight
    if (r < DISK_INNER * 0.95 || r > DISK_OUTER * 1.02) return vec4(0.0);
    if (verticalW < 0.001) return vec4(0.0);

    float phi = atan(p.z, p.x);
    float posY = p.y;  // Store actual y position for vertical oscillations
    float H = getDiskScaleHeight(r);  // Get scale height for this radius
    float omega = sqrt(M / (r * r * r));
    float rotPhi = phi + time * omega * 0.35;

    // ═══ MULTI-SCALE TURBULENCE (Phase 2) ═══

    // Large-scale turbulence (clumps and voids)
    float turb1 = noise(vec3(r * 0.4, rotPhi * 0.8, time * 0.4)) - 0.5;
    // Medium-scale turbulence (density variations)
    float turb2 = noise(vec3(r * 1.2, rotPhi * 2.5, time * 0.8)) - 0.5;
    // Fine-scale turbulence (modulates fine filaments)
    float turb3 = noise(vec3(r * 2.5, rotPhi * 5.0, time * 1.2)) - 0.5;

    float turbulence = turb1 * 0.5 + turb2 * 0.3;

    // Create turbulence masks for filament modulation
    float turbMaskLarge = smoothstep(-0.3, 0.4, turb1);   // Large clumpy regions
    float turbMaskMed = smoothstep(-0.2, 0.3, turb2);     // Medium density variation
    float turbMaskFine = 0.6 + turb3 * 0.8;               // Fine detail modulation

    // Phase displacement from turbulence (makes filaments wavy/distorted)
    float phaseDisturb = turb1 * 3.0 + turb2 * 1.5;

    // ═══ ULTRA-DENSE FILAMENT SYSTEM (Phase 1) ═══
    // Precompute shared winding values
    float shearAngle = rotPhi - (DISK_OUTER - r) * 0.8;
    float spiralWind = log(r / DISK_INNER + 0.1);
    float tOmega = time * omega;  // Precompute for reuse

    // === FREQUENCY CASCADE with turbulence modulation ===

    // Band 1: Base structure (freq 40-60) - modulated by large turbulence
    float b1a = sin(rotPhi * 40.0 - spiralWind * 12.0 + tOmega * 2.0 + phaseDisturb);
    float b1b = sin(rotPhi * 55.0 + spiralWind * 10.0 - tOmega * 1.8 + phaseDisturb * 0.8);
    b1a = pow(max(b1a, 0.0), 4.0);
    b1b = pow(max(b1b, 0.0), 4.0);
    float band1 = (b1a * 0.5 + b1b * 0.5) * turbMaskLarge;

    // Band 2: Medium detail (freq 80-120) - modulated by medium turbulence
    float b2a = sin(rotPhi * 85.0 - spiralWind * 14.0 + tOmega * 1.5 + phaseDisturb * 0.6);
    float b2b = sin(rotPhi * 100.0 + spiralWind * 8.0 - tOmega * 2.2 + phaseDisturb * 0.5);
    float b2c = sin(rotPhi * 115.0 - spiralWind * 11.0 + tOmega * 1.2 + phaseDisturb * 0.4);
    b2a = pow(max(b2a, 0.0), 5.0);
    b2b = pow(max(b2b, 0.0), 5.0);
    b2c = pow(max(b2c, 0.0), 5.0);
    float band2 = (b2a * 0.35 + b2b * 0.35 + b2c * 0.3) * turbMaskMed;

    // Band 3: Fine detail (freq 160-220) - modulated by fine turbulence
    float b3a = sin(rotPhi * 160.0 - spiralWind * 16.0 + tOmega + phaseDisturb * 0.3);
    float b3b = sin(rotPhi * 190.0 + spiralWind * 6.0 - tOmega * 1.5 + phaseDisturb * 0.25);
    float b3c = sin(rotPhi * 220.0 - spiralWind * 18.0 + tOmega * 0.8 + phaseDisturb * 0.2);
    b3a = pow(max(b3a, 0.0), 6.0);
    b3b = pow(max(b3b, 0.0), 6.0);
    b3c = pow(max(b3c, 0.0), 6.0);
    float band3 = (b3a * 0.35 + b3b * 0.35 + b3c * 0.3) * turbMaskFine;

    // Band 4: Ultra-fine detail (freq 300-400) - optimized: 2 layers instead of 3
    float b4a = sin(rotPhi * 300.0 - spiralWind * 20.0 + tOmega * 0.5);
    float b4b = sin(rotPhi * 400.0 + spiralWind * 5.0 - tOmega);
    b4a = pow(max(b4a, 0.0), 7.0);
    b4b = pow(max(b4b, 0.0), 7.0);
    float band4 = (b4a * 0.5 + b4b * 0.5) * turbMaskFine * turbMaskMed;

    // Radial infall streaks (plunging matter near ISCO) - chaotic modulation
    float infall1 = sin(shearAngle * 120.0 + r * 8.0 - time * 2.5 + phaseDisturb);
    float infall2 = sin(shearAngle * 200.0 - r * 12.0 + time * 1.8 + phaseDisturb * 0.7);
    infall1 = pow(max(infall1, 0.0), 6.0);
    infall2 = pow(max(infall2, 0.0), 7.0);
    float infallMask = smoothstep(DISK_OUTER * 0.5, DISK_INNER * 1.2, r);
    float infallStreaks = (infall1 * 0.5 + infall2 * 0.5) * infallMask * (0.5 + turbMaskLarge * 0.5);

    // Edge falloff mask
    float filamentMask = smoothstep(DISK_INNER * 0.98, DISK_INNER * 1.15, r) *
                         smoothstep(DISK_OUTER * 1.02, DISK_OUTER * 0.85, r);

    // ═══ VERTICAL OSCILLATION (Phase 3) - Optimized: 2 bands instead of 4 ═══
    // Combine bands into 2 groups for efficiency
    float vOsc1 = getVerticalOscillation(phi, r, time, 60.0, 0.0, omega);
    float vOsc2 = getVerticalOscillation(phi, r, time, 200.0, 1.5, omega);

    // Calculate vertical weight for each band group
    float vWeight1 = verticalDensity(posY - vOsc1 * r, H);
    float vWeight2 = verticalDensity(posY - vOsc2 * r, H);

    // Normalize weights
    float baseW = max(verticalW, 0.01);
    vWeight1 = vWeight1 / baseW;
    vWeight2 = vWeight2 / baseW;

    // Combine bands: group low-freq (1,2) and high-freq (3,4) together
    float lowFreqBands = band1 * 0.30 + band2 * 0.28;
    float highFreqBands = band3 * 0.22 + band4 * 0.12;

    float filaments = (lowFreqBands * vWeight1 + highFreqBands * vWeight2 +
                       infallStreaks * 0.08) * filamentMask;

    // ═══ FINE GRAIN TEXTURE (Phase 3) ═══
    // Hash-based micro-texture - extremely cheap, adds surface roughness

    // Coordinates that move with disk rotation
    float grainPhi = rotPhi * 800.0;  // Very high frequency
    float grainR = r * 100.0;

    // Multi-scale grain layers using fast hash
    float grain1 = hash2(vec2(grainPhi, grainR));
    float grain2 = hash2(vec2(grainPhi * 0.7 + 100.0, grainR * 1.3));
    float grain3 = hash2(vec2(grainPhi * 1.5 + 200.0, grainR * 0.8 + time * 5.0));

    // Threshold to create sparse bright specks
    grain1 = smoothstep(0.75, 0.95, grain1);
    grain2 = smoothstep(0.80, 0.98, grain2);
    grain3 = smoothstep(0.85, 0.99, grain3);  // Animated flickering specks

    // Combine grain layers - finer toward center
    float grainDensity = smoothstep(DISK_OUTER, DISK_INNER * 2.0, r);
    float grain = (grain1 * 0.4 + grain2 * 0.35 + grain3 * 0.25) * grainDensity * 0.3;

    // Add subtle continuous micro-variation
    float microVar = hash2(vec2(grainPhi * 0.3, grainR * 0.5)) * 0.15;

    // Combine grain with filaments
    filaments += grain + microVar * filamentMask;

    // ═══ MAGNETIC FIELD ALIGNED STRUCTURES (Phase 6) ═══
    // Anisotropic texture that follows magnetic field topology

    // Blend factor: 0 = azimuthal (orbiting), 1 = radial (plunging)
    float radialBlend = smoothstep(DISK_INNER * 2.5, DISK_INNER * 1.0, r);

    // Azimuthal structures (dominant in mid/outer disk - orbiting gas)
    float azimuthal1 = sin(rotPhi * 150.0 + time * omega * 0.8);
    float azimuthal2 = sin(rotPhi * 220.0 - time * omega * 0.6);
    azimuthal1 = pow(max(azimuthal1, 0.0), 6.0);
    azimuthal2 = pow(max(azimuthal2, 0.0), 7.0);
    float azimuthalField = (azimuthal1 * 0.5 + azimuthal2 * 0.5);

    // Radial structures (dominant near ISCO - plunging gas)
    float radial1 = sin(phi * 60.0 + r * 25.0 - time * 3.0);
    float radial2 = sin(phi * 90.0 - r * 30.0 + time * 2.5);
    radial1 = pow(max(radial1, 0.0), 5.0);
    radial2 = pow(max(radial2, 0.0), 6.0);
    float radialField = (radial1 * 0.5 + radial2 * 0.5);

    // Twisted field lines (magnetic field gets wound by differential rotation)
    float twist = sin(rotPhi * 100.0 + r * 15.0 - spiralWind * 5.0 + time * 0.8);
    twist = pow(max(twist, 0.0), 5.0) * 0.6;

    // Blend between azimuthal and radial based on radius
    float magField = mix(azimuthalField, radialField, radialBlend) + twist * (1.0 - radialBlend * 0.5);

    // Apply turbulence modulation to magnetic structures
    magField *= turbMaskMed * 0.8 + 0.2;

    // Add magnetic field texture to filaments
    filaments += magField * filamentMask * 0.2;

    // ═══ ENHANCED MULTI-ARM SPIRAL SYSTEM (Phase 4) ═══
    float logR = log(r / DISK_INNER + 0.1);

    // Primary 2-arm spiral (grand design) - slow rotation
    float spiral2angle = phi - logR * 2.0 + time * 0.2;
    float spiral2 = sin(spiral2angle * 2.0);
    float shock2 = smoothstep(0.3, 0.95, spiral2);  // Sharp leading edge
    shock2 = pow(shock2, 1.5);  // Extra sharpness

    // Secondary 3-arm spiral - faster, tighter winding
    float spiral3angle = phi - logR * 2.8 + time * 0.35;
    float spiral3 = sin(spiral3angle * 3.0);
    float shock3 = smoothstep(0.4, 0.9, spiral3);

    // Tertiary 5-arm fine ripples - fastest, creates texture
    float spiral5angle = phi - logR * 3.5 + time * 0.5;
    float spiral5 = sin(spiral5angle * 5.0);
    float shock5 = smoothstep(0.5, 0.85, spiral5);
    shock5 *= 0.6;  // Subtler

    // Fine trailing ripples behind main arms
    float rippleAngle = phi - logR * 4.0 - time * 0.15;
    float ripples = sin(rippleAngle * 8.0) * 0.5 + 0.5;
    ripples = pow(ripples, 3.0) * 0.4;

    // Combine spirals with radius-dependent strength
    float innerSpiral = smoothstep(DISK_OUTER, DISK_INNER * 2.0, r);  // Stronger near center
    float outerSpiral = smoothstep(DISK_INNER, DISK_INNER * 3.0, r);  // Fade at very inner edge
    float spiralMask = innerSpiral * outerSpiral;

    float shockFront = (shock2 * 0.4 + shock3 * 0.3 + shock5 * 0.2 + ripples * 0.1) * spiralMask;
    float spiralStrength = 0.5 + 0.5 * exp(-pow((r - DISK_INNER * 2.0) / 5.0, 2.0));

    // ═══ HOT SPOTS (larger, brighter flares) ═══
    float hotSpots = 0.0;
    for (int i = 0; i < 5; i++) {
        float spotR = DISK_INNER * (1.1 + float(i) * 0.5);
        float spotOmega = sqrt(M / (spotR * spotR * spotR));
        float spotPhi = float(i) * 1.26 + time * spotOmega * 0.5;

        // Flare timing - faster pulsing
        float flarePhase = sin(time * (0.6 + float(i) * 0.2) + float(i) * 2.0);
        float flarePower = smoothstep(0.2, 0.85, flarePhase);

        // Larger hot spots (visible from distance)
        float dphi = mod(phi - spotPhi + PI, 2.0 * PI) - PI;
        float dist2 = (r - spotR) * (r - spotR) + (dphi * r) * (dphi * r);

        hotSpots += flarePower * exp(-dist2 * 0.25) * 0.7;  // Larger radius
    }

    // ═══ ISCO CHAOS ZONE (extended, more violent) ═══
    // Extends further out, more dramatic
    float iscoProximity = 1.0 - clamp((r - DISK_INNER) / (DISK_INNER * 0.8), 0.0, 1.0);
    float chaos = 0.0;
    if (iscoProximity > 0.0) {
        // Chaotic flickering - faster
        chaos = noise(vec3(phi * 6.0, r * 3.0, time * 3.5)) * iscoProximity;
        // Radial plunging streaks - more visible
        float plunge = sin(phi * 10.0 + r * 4.0 - time * 5.0);
        plunge = max(plunge, 0.0);
        chaos += plunge * plunge * iscoProximity * 0.7;
    }

    // ═══ DENSITY (higher contrast) ═══
    float innerEdge = smoothstep(DISK_INNER * 0.95, DISK_INNER * 1.02, r);
    float outerEdge = smoothstep(DISK_OUTER * 1.02, DISK_OUTER * 0.9, r);

    float density = innerEdge * outerEdge;
    // Stronger turbulence contrast
    float turbContrast = turbulence * 1.5;
    turbContrast = sign(turbContrast) * pow(abs(turbContrast), 0.7);  // Boost subtle variations
    density *= 0.45 + 0.4 * turbContrast + 0.25 * shockFront * spiralStrength;
    density += chaos * 0.5;

    // Add filament detail to density
    density += filaments * 0.25;

    // Inner edge glow
    float innerDist = (r - DISK_INNER) / 0.5;
    float innerGlow = exp(-innerDist * innerDist);
    density += innerGlow * 0.8;

    // ═══ TEMPERATURE with filament color variation (Phase 5) ═══
    float temp = pow(DISK_INNER / r, 0.85);
    temp += innerGlow * 0.35;
    temp += shockFront * spiralStrength * 0.25;  // Shock heating
    temp += hotSpots * 0.4;                       // Flare heating
    temp += chaos * 0.3;                          // ISCO heating

    // Filament temperature variation - cores are hotter
    float filamentHeat = filaments * 0.25;        // Base filament heating
    filamentHeat += band1 * 0.15;                 // Large filaments extra heat
    filamentHeat += grain * 0.2;                  // Grain specks are hot
    temp += filamentHeat;

    // Temperature variation along filaments (creates color streaks)
    float tempVariation = sin(rotPhi * 25.0 - spiralWind * 8.0 + time * 0.5) * 0.5 + 0.5;
    temp += tempVariation * filaments * 0.12;

    // Einstein ring boost - stronger for secondary images
    float crossingBoost = 1.0;
    if (crossingNum == 2) {
        crossingBoost = 2.5;  // First secondary image - very bright
        temp *= 1.2;          // Hotter appearance
    } else if (crossingNum > 2) {
        crossingBoost = 3.0 + float(crossingNum) * 0.5;  // Higher order images
        temp *= 1.3;
    }

    // ═══ DOPPLER ═══
    float dopplerFac = 1.0;
    if (uDoppler > 0.5) {
        float vOrb = min(sqrt(M / r), 0.45);
        vec3 velDir = normalize(vec3(-p.z, 0.0, p.x));
        float vLos = dot(velDir, rayDir) * vOrb;

        // Relativistic Doppler factor
        float g = clamp(1.0 / (1.0 - vLos), 0.4, 2.5);

        // Brightness asymmetry
        dopplerFac = pow(g, 2.0);

        // Temperature shift
        temp *= clamp(g, 0.7, 1.4);
    }

    // ═══ REDSHIFT ═══
    float gravFac = uRedshift > 0.5 ? sqrt(max(0.2, 1.0 - RS / r)) : 1.0;

    // ═══ EMISSION COLOR with enhanced variation (Phase 5) ═══
    vec3 emission = interstellarDiskColor(temp * gravFac);

    // Filament cores glow brighter/whiter
    vec3 filamentGlow = vec3(1.0, 0.92, 0.8);  // Warm white
    emission = mix(emission, emission * filamentGlow, filaments * 0.4);

    // Fine grain creates bright specks
    vec3 grainGlow = vec3(1.0, 0.95, 0.85);
    emission = mix(emission, grainGlow, grain * 0.6);

    // Hot spots add white-hot glow
    emission = mix(emission, vec3(1.0, 0.95, 0.85), hotSpots * 0.5);

    // Spiral shock fronts have slight color shift (compressed/heated gas)
    vec3 shockColor = vec3(1.0, 0.88, 0.7);
    emission = mix(emission, emission * shockColor, shockFront * 0.25);

    // Chaos adds intense orange-white brightness
    emission += vec3(1.0, 0.8, 0.5) * chaos * 0.35;

    // Subtle color variation from turbulence (breaks up uniformity)
    float colorShift = turb2 * 0.08;
    emission.r *= 1.0 + colorShift;
    emission.b *= 1.0 - colorShift * 0.5;

    // Volumetric integration: apply vertical density profile and step length
    // Opacity per unit length scaled by step
    float kappa = density * verticalW * 2.5;  // Absorption coefficient
    float dTau = kappa * stepLen;
    dTau = clamp(dTau, 0.0, 4.0);
    float alpha = 1.0 - exp(-dTau);

    return vec4(emission * dopplerFac * gravFac * crossingBoost, alpha);
}

// ═══════════════════════════════════════════════════════════════════════════
// STARFIELD (Maximum density, slightly sharper)
// ═══════════════════════════════════════════════════════════════════════════

vec3 stars(vec3 dir, float lensing) {
    vec3 col = vec3(0.0);

    // Layer 1: Ultra-dense faint stars (background dust)
    vec3 p1 = dir * 20.0;
    vec3 id1 = floor(p1);
    float rnd1 = hash3(id1);
    if (rnd1 > 0.65) {  // Even denser
        vec3 f1 = fract(p1) - 0.5;
        float d1 = length(f1);
        float b1 = exp(-d1 * d1 * 90.0) * lensing * 0.45;  // Sharper
        col += vec3(1.0, 0.98, 0.96) * b1;
    }

    // Layer 2: Dense small stars
    vec3 p2 = dir * 40.0;
    vec3 id2 = floor(p2);
    float rnd2 = hash3(id2 + 30.0);
    if (rnd2 > 0.70) {  // Denser
        vec3 f2 = fract(p2) - 0.5;
        float d2 = length(f2);
        float b2 = exp(-d2 * d2 * 75.0) * lensing * 0.6;  // Sharper
        col += vec3(0.95, 0.97, 1.0) * b2;
    }

    // Layer 3: Medium stars
    vec3 p3 = dir * 65.0;
    vec3 id3 = floor(p3);
    float rnd3 = hash3(id3 + 60.0);
    if (rnd3 > 0.78) {  // Denser
        vec3 f3 = fract(p3) - 0.5;
        float d3 = length(f3);
        float b3 = exp(-d3 * d3 * 55.0) * lensing * 0.8;  // Sharper
        vec3 starCol = rnd3 > 0.90 ? vec3(1.0, 0.85, 0.65) : vec3(0.85, 0.92, 1.0);
        col += starCol * b3;
    }

    // Layer 4: Bright accent stars
    vec3 p4 = dir * 95.0;
    vec3 id4 = floor(p4);
    float rnd4 = hash3(id4 + 100.0);
    if (rnd4 > 0.88) {  // Denser
        vec3 f4 = fract(p4) - 0.5;
        float d4 = length(f4);
        float b4 = exp(-d4 * d4 * 40.0) * lensing * 1.1;  // Sharper
        vec3 starCol = rnd4 > 0.94 ? vec3(1.0, 0.7, 0.5) : vec3(0.75, 0.85, 1.0);
        col += starCol * b4;
    }

    // Layer 5: Rare bright giants
    vec3 p5 = dir * 120.0;
    vec3 id5 = floor(p5);
    float rnd5 = hash3(id5 + 150.0);
    if (rnd5 > 0.95) {
        vec3 f5 = fract(p5) - 0.5;
        float d5 = length(f5);
        float b5 = exp(-d5 * d5 * 30.0) * lensing * 1.4;
        vec3 starCol = rnd5 > 0.975 ? vec3(1.0, 0.6, 0.4) : vec3(0.7, 0.8, 1.0);
        col += starCol * b5;
    }

    return col * 0.55;  // Slightly brighter
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN RAY TRACER WITH EINSTEIN RING
// ═══════════════════════════════════════════════════════════════════════════

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;

    // Camera setup from uniforms
    float dist = uCamDistance > 0.0 ? uCamDistance : CAM_DIST_DEFAULT;
    float zoom = uCamZoom > 0.0 ? uCamZoom : CAM_ZOOM_DEFAULT;

    // Spherical to Cartesian conversion for camera position
    // Elevation: 0 = equator, PI/2 = north pole, -PI/2 = south pole
    // Azimuth: angle around Y axis
    float cosElev = cos(uCamElevation);
    float sinElev = sin(uCamElevation);
    float cosAzi = cos(uCamAzimuth);
    float sinAzi = sin(uCamAzimuth);

    vec3 ro = vec3(
        dist * cosElev * sinAzi,
        dist * sinElev,
        dist * cosElev * cosAzi
    );
    vec3 target = vec3(0.0, 0.0, 0.0);

    vec3 forward = normalize(target - ro);

    // Handle gimbal lock near poles
    vec3 worldUp = abs(sinElev) > 0.99 ? vec3(0.0, 0.0, -sign(sinElev)) : vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(forward, worldUp));
    vec3 up = cross(right, forward);

    vec3 rd = normalize(uv.x * right + uv.y * up + zoom * forward);

    // Ray state
    vec3 pos = ro;
    vec3 vel = rd;

    // Accumulation
    vec3 col = vec3(0.0);
    float transmission = 1.0;
    float minR = length(pos);

    // Track disk crossings for Einstein ring effect
    int diskCrossings = 0;
    float lastY = pos.y;

    // Track closest approach to photon sphere for ring rendering
    float minPhotonDist = 100.0;

    // Main integration loop
    for (int i = 0; i < MAX_STEPS; i++) {
        float r = length(pos);
        minR = min(minR, r);
        minPhotonDist = min(minPhotonDist, abs(r - PHOTON_SPHERE));

        // Event horizon - absorbed
        if (r < RS * 0.52) {
            transmission = 0.0;
            break;
        }

        // Opacity saturated
        if (transmission < 0.01) break;

        // Early termination - only after ray has approached BH
        if (minR < 30.0) {
            float radialVel = dot(normalize(pos), vel);
            if (r > 50.0 && radialVel > 0.2) break;
        }

        // Gravitational acceleration
        vec3 accel = blackHoleAccel(pos);

        // ═══ ADAPTIVE STEPPING (optimized for extended range) ═══
        // Coarser steps when zoomed in (closer camera = more rays through disk)
        float zoomFactor = smoothstep(20.0, 40.0, uCamDistance);  // 1.0 at far, 0.0 at close
        float baseStep = STEP_SIZE * (1.0 + (1.0 - zoomFactor) * 0.4);  // Up to 40% larger steps when close

        float h = baseStep;
        if (r < PHOTON_SPHERE + 0.3) {
            h *= 0.2;   // Fine near photon sphere
        } else if (r < 5.0) {
            h *= 0.5;   // Medium in strong field
        } else if (r < 12.0) {
            h *= 1.0;   // Normal near disk
        } else if (r < 20.0) {
            h *= 1.5;   // Slightly coarse
        } else if (r < 35.0) {
            h *= 2.5;   // Coarse
        } else if (r < 60.0) {
            h *= 4.0;   // Very coarse
        } else {
            h *= 6.0;   // Ultra coarse far field
        }

        // Leapfrog integration
        vec3 velHalf = vel + accel * h * 0.5;
        vec3 newPos = pos + velHalf * h;
        vec3 newAccel = blackHoleAccel(newPos);
        vec3 newVel = velHalf + newAccel * h * 0.5;
        newVel = normalize(newVel);


        // ═══════════════════════════════════════════════════════════════════
        // VOLUMETRIC DISK SAMPLING - Continuous integration through disk volume
        // ═══════════════════════════════════════════════════════════════════

        // Track plane crossings for Einstein ring boost
        bool crossedPlane = (lastY * newPos.y < 0.0);
        if (crossedPlane) {
            diskCrossings++;
        }

        // Sample disk volumetrically at midpoint of step
        vec3 midPos = (pos + newPos) * 0.5;
        float diskR = length(midPos.xz);

        // Check if within disk radial bounds
        if (diskR > DISK_INNER * 0.92 && diskR < DISK_OUTER * 1.08) {
            // Get scale height at this radius
            float H = getDiskScaleHeight(diskR);

            // Apply FBM vertical warp - creates large-scale 3D turbulent structure
            float diskPhi = atan(midPos.z, midPos.x);
            float vertWarp = getVerticalWarp(diskPhi, diskR, uTime);
            float warpedY = midPos.y - vertWarp * diskR;
            float diskY = abs(warpedY);

            // Only sample within cutoff scale heights
            if (diskY < H * DISK_CUTOFF) {
                // Gaussian vertical density profile with warped position
                float verticalW = verticalDensity(warpedY, H);

                // Skip negligible contributions - higher threshold when zoomed in
                float zoomThreshold = 0.04 + (1.0 - smoothstep(20.0, 40.0, uCamDistance)) * 0.04;
                if (verticalW > zoomThreshold) {
                    // Sample the disk with volumetric parameters
                    vec4 diskData = sampleDiskVolumetric(midPos, vel, uTime, diskCrossings, verticalW, h);

                    if (diskData.a > 0.002) {
                        // Intensity scales with how close we are to photon sphere
                        float photonBoost = 1.0 + exp(-minPhotonDist * minPhotonDist * 2.0);

                        // Volumetric accumulation
                        col += diskData.rgb * diskData.a * transmission * photonBoost;
                        transmission *= (1.0 - diskData.a);

                        if (transmission < 0.01) break;
                    }
                }
            }
        }

        lastY = pos.y;
        pos = newPos;
        vel = newVel;

        // Escaped - only after approaching the BH
        if (r > 120.0 && minR < 40.0) break;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHOTON RING - Dramatic multi-layered with animation
    // ═══════════════════════════════════════════════════════════════════════

    // Get angle around the black hole for ring animation
    float ringAngle = atan(vel.z, vel.x);

    // Flowing hot spots - more dramatic variation
    float ringFlow1 = sin(ringAngle * 3.0 - uTime * 1.5) * 0.5 + 0.5;
    float ringFlow2 = sin(ringAngle * 7.0 + uTime * 1.0) * 0.5 + 0.5;
    float ringFlow3 = sin(ringAngle * 2.0 - uTime * 0.6) * 0.5 + 0.5;
    float ringFlow = 0.5 + 0.5 * ringFlow1 * ringFlow2 * (0.7 + 0.3 * ringFlow3);

    // Pulsating brightness
    float ringPulse = 0.8 + 0.2 * sin(uTime * 2.5 + ringAngle * 3.0);

    // Outer glow - soft wide halo
    float ring0Dist = abs(minR - PHOTON_SPHERE * 1.05);
    float ring0 = exp(-ring0Dist * ring0Dist * 4.0) * 0.4;

    // Primary photon ring - main visible ring
    float ring1Dist = abs(minR - PHOTON_SPHERE);
    float ring1 = exp(-ring1Dist * ring1Dist * 10.0) * 0.9;

    // Secondary ring - tighter
    float ring2Dist = abs(minR - PHOTON_SPHERE * 0.96);
    float ring2 = exp(-ring2Dist * ring2Dist * 30.0) * 0.7;

    // Tertiary ring - sharp
    float ring3Dist = abs(minR - PHOTON_SPHERE * 0.93);
    float ring3 = exp(-ring3Dist * ring3Dist * 60.0) * 0.5;

    // Inner bright edge
    float ring4Dist = abs(minR - PHOTON_SPHERE * 0.90);
    float ring4 = exp(-ring4Dist * ring4Dist * 100.0) * 0.4;

    float totalRing = (ring0 + ring1 + ring2 + ring3 + ring4) * ringFlow * ringPulse;

    // Rich color gradient around the ring
    float colorPhase = ringAngle * 0.5 - uTime * 0.4;
    vec3 ringColor1 = vec3(1.0, 0.85, 0.5);   // Golden
    vec3 ringColor2 = vec3(1.0, 0.7, 0.35);   // Orange-gold
    vec3 ringColor = mix(ringColor1, ringColor2, sin(colorPhase) * 0.5 + 0.5);

    // Add brightness boost near the disk plane
    float diskPlaneBoost = 1.0 + 0.5 * exp(-vel.y * vel.y * 20.0);

    col += ringColor * totalRing * transmission * 1.5 * diskPlaneBoost;

    // Lensing amplification glow - animated
    float lensingGlow = exp(-minPhotonDist * minPhotonDist * 0.5) * 0.3;
    lensingGlow *= 0.8 + 0.2 * sin(uTime * 1.5 + ringAngle * 4.0);
    col += vec3(1.0, 0.85, 0.6) * lensingGlow * transmission;

    // Shadow edge definition
    float shadowR = RS * 0.52;
    float edgeDist = minR - shadowR;
    float edgeGlow = exp(-edgeDist * edgeDist * 2.0) * 0.08;
    col += vec3(0.6, 0.3, 0.1) * edgeGlow * transmission;

    // Background stars
    if (transmission > 0.01) {
        float lensAmp = 1.0 + 3.0 * exp(-minPhotonDist * minPhotonDist);
        col += stars(vel, lensAmp) * transmission;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POST-PROCESSING - Cinematic film look
    // ═══════════════════════════════════════════════════════════════════════

    // Multi-level bloom for cinematic glow
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float softBloom = smoothstep(0.2, 0.8, lum) * 0.35;   // Soft overall glow
    float hotBloom = smoothstep(0.6, 1.2, lum) * 0.5;     // Hot highlights
    col *= 1.0 + softBloom + hotBloom;

    // ACES filmic tone mapping with adjusted exposure
    col *= 0.45;
    col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
    col = pow(col, vec3(0.4545));  // Gamma 2.2

    // Subtle warm color grade
    col.r *= 1.03;
    col.g *= 1.0;
    col.b *= 0.94;

    // Gentle contrast enhancement
    float lumFinal = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, col * col * (3.0 - 2.0 * col), 0.3);

    // Vignette - slightly stronger
    float vigDist = length(uv * 0.75);
    col *= 1.0 - 0.4 * pow(vigDist, 2.8);

    // Film grain (organic, subtle)
    float grain = (hash2(uv * 600.0 + fract(uTime * 0.5)) - 0.5);
    col += grain * 0.022 * (1.0 - lumFinal * 0.5);  // Less grain in highlights

    // Ensure blacks stay black
    col = max(col, vec3(0.0));

    gl_FragColor = vec4(col, 1.0);
}
