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

// Accretion disk - thin and crisp like Interstellar
#define DISK_INNER 3.0
#define DISK_OUTER 15.0
#define DISK_HEIGHT 0.015       // Very thin disk for sharp look

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

// Sample disk - DYNAMIC with turbulence, flares, and chaos
vec4 sampleDisk(vec3 p, vec3 rayDir, float time, int crossingNum) {
    float r = length(p.xz);

    // Early out - disk bounds
    if (r < DISK_INNER * 0.95 || r > DISK_OUTER * 1.02) return vec4(0.0);

    float phi = atan(p.z, p.x);
    float omega = sqrt(M / (r * r * r));
    float rotPhi = phi + time * omega * 0.35;

    // ═══ TURBULENT STRUCTURE (larger scale, faster) ═══

    // Multi-scale turbulence - bigger features visible from afar
    float turb1 = noise(vec3(r * 0.5, rotPhi * 1.0, time * 0.5)) - 0.5;
    float turb2 = noise(vec3(r * 1.5, rotPhi * 3.0, time * 1.0)) - 0.5;
    float turbulence = turb1 * 0.5 + turb2 * 0.3;

    // ═══ SPIRAL SHOCK WAVES (more prominent) ═══
    // Two-armed spiral - larger, faster rotation
    float spiralAngle = phi - log(r / DISK_INNER + 0.1) * 2.0 + time * 0.25;
    float spiral = sin(spiralAngle * 2.0);
    float shockFront = smoothstep(0.4, 0.9, spiral);  // Sharp leading edge
    float spiralStrength = 0.4 + 0.6 * exp(-pow((r - DISK_INNER * 2.5) / 6.0, 2.0));

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

    // Inner edge glow
    float innerDist = (r - DISK_INNER) / 0.5;
    float innerGlow = exp(-innerDist * innerDist);
    density += innerGlow * 0.8;

    // ═══ TEMPERATURE ═══
    float temp = pow(DISK_INNER / r, 0.85);
    temp += innerGlow * 0.35;
    temp += shockFront * spiralStrength * 0.2;  // Shock heating
    temp += hotSpots * 0.4;                      // Flare heating
    temp += chaos * 0.3;                         // ISCO heating

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

    // ═══ EMISSION COLOR ═══
    vec3 emission = interstellarDiskColor(temp * gravFac);

    // Hot spots add white-hot glow
    emission = mix(emission, vec3(1.0, 0.95, 0.85), hotSpots * 0.4);

    // Chaos adds intense brightness
    emission += vec3(1.0, 0.8, 0.5) * chaos * 0.3;

    return vec4(emission, density * dopplerFac * gravFac * crossingBoost);
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
        float h = STEP_SIZE;
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
        // DISK CROSSING DETECTION - Key for Einstein ring!
        // ═══════════════════════════════════════════════════════════════════

        bool crossedDisk = (lastY * newPos.y < 0.0);

        if (crossedDisk) {
            diskCrossings++;

            // Interpolate to find exact crossing point
            float t = abs(lastY) / (abs(lastY) + abs(newPos.y) + 1e-6);
            vec3 crossPos = mix(pos, newPos, t);
            float crossR = length(crossPos.xz);

            // Sample disk if within bounds
            if (crossR > DISK_INNER * 0.9 && crossR < DISK_OUTER * 1.1) {
                vec4 diskData = sampleDisk(crossPos, vel, uTime, diskCrossings);

                if (diskData.a > 0.001) {
                    // Intensity scales with how close we are to photon sphere
                    float photonBoost = 1.0 + exp(-minPhotonDist * minPhotonDist * 2.0);
                    float light = diskData.a * 0.9 * photonBoost;

                    col += diskData.rgb * light * transmission;
                    transmission *= exp(-light * 0.3);

                    if (transmission < 0.01) break;
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
