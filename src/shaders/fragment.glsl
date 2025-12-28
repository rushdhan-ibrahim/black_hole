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

// Integration - more steps for better photon sphere resolution
#define MAX_STEPS 500
#define STEP_SIZE 0.12

// Black hole
#define M 1.0
#define RS 2.0                  // Schwarzschild radius
#define PHOTON_SPHERE 3.0       // Photon sphere at 1.5 * RS

// Accretion disk
#define DISK_INNER 3.0
#define DISK_OUTER 14.0
#define DISK_HEIGHT 0.05        // Thinner disk for sharper look

// Camera defaults (now controlled by uniforms)
#define CAM_DIST_DEFAULT 35.0
#define CAM_ZOOM_DEFAULT 1.8

// ═══════════════════════════════════════════════════════════════════════════
// NOISE
// ═══════════════════════════════════════════════════════════════════════════

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

float noise(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0 + 113.0 * p.z;
    return mix(mix(mix(hash(n), hash(n + 1.0), f.x),
                   mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

float fbm(vec3 p) {
    float f = 0.0;
    float w = 0.5;
    for (int i = 0; i < 4; i++) {
        f += w * noise(p);
        p *= 2.03;
        w *= 0.5;
    }
    return f;
}

// ═══════════════════════════════════════════════════════════════════════════
// GRAVITATIONAL PHYSICS
// ═══════════════════════════════════════════════════════════════════════════

vec3 blackHoleAccel(vec3 pos) {
    float r = length(pos);
    if (r < 0.1) return vec3(0.0);

    vec3 dir = -normalize(pos);

    // Schwarzschild-like acceleration with GR corrections
    // The 1.5 factor gives correct photon sphere location
    float accel = 1.5 * M * RS / (r * r * r);

    // Enhanced bending near photon sphere
    float photonFactor = 1.0 + 2.0 * exp(-pow(r - PHOTON_SPHERE, 2.0) * 0.5);

    return dir * accel * photonFactor;
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCRETION DISK
// ═══════════════════════════════════════════════════════════════════════════

float keplerOmega(float r) {
    return sqrt(M / (r * r * r));
}

vec3 blackbody(float temp) {
    float t = temp * 10.0;

    vec3 col;
    if (t < 3.0) {
        // Deep red/orange
        col = vec3(1.0, 0.3 * t / 3.0, 0.0);
    } else if (t < 5.5) {
        // Orange to yellow
        float s = (t - 3.0) / 2.5;
        col = vec3(1.0, 0.3 + 0.5 * s, 0.1 * s);
    } else if (t < 8.0) {
        // Yellow to white-yellow
        float s = (t - 5.5) / 2.5;
        col = vec3(1.0, 0.8 + 0.15 * s, 0.1 + 0.4 * s);
    } else {
        // White-hot
        float s = min((t - 8.0) / 4.0, 1.0);
        col = vec3(1.0, 0.95, 0.5 + 0.4 * s);
    }
    return col;
}

// Sample disk - returns (color.rgb, intensity)
vec4 sampleDisk(vec3 p, vec3 rayDir, float time, int crossingNum) {
    float r = length(p.xz);
    float y = p.y;

    // Disk bounds
    if (r < DISK_INNER * 0.95 || r > DISK_OUTER * 1.05) return vec4(0.0);

    // Very thin disk
    float H = DISK_HEIGHT * (1.0 + 0.3 * (r - DISK_INNER) / DISK_INNER);

    // Keplerian rotation
    float omega = keplerOmega(r);
    float phi = atan(p.z, p.x);
    float rotPhi = phi + time * omega * 0.4;

    // Turbulent structure
    vec3 noiseCoord = vec3(r * 1.2, rotPhi * 2.5, 0.0);
    float turb = fbm(noiseCoord);

    // Spiral arms
    float spiral = sin(rotPhi * 2.0 + log(r + 1.0) * 4.0);
    spiral = 0.5 + 0.5 * spiral;

    // Density - sharper edges
    float radialFade = smoothstep(DISK_INNER * 0.95, DISK_INNER + 0.3, r);
    radialFade *= smoothstep(DISK_OUTER * 1.05, DISK_OUTER - 1.0, r);

    float density = radialFade;
    density *= 0.6 + 0.25 * turb + 0.15 * spiral;

    // Bright inner edge (ISCO glow)
    float innerGlow = exp(-pow((r - DISK_INNER) / 0.5, 2.0));
    density += innerGlow * 0.8;

    // Temperature profile - Novikov-Thorne inspired
    float temp = pow(DISK_INNER / r, 0.75);
    temp *= 0.85 + 0.15 * turb;
    temp += innerGlow * 0.3;  // Extra hot at inner edge

    // Boost for secondary crossings (Einstein ring contribution)
    // Secondary images are from light that wrapped around
    float crossingBoost = 1.0;
    if (crossingNum > 1) {
        crossingBoost = 1.5 + float(crossingNum - 1) * 0.5;
        temp *= 1.1;  // Slightly hotter appearance for lensed light
    }

    // Doppler beaming
    float dopplerFac = 1.0;
    if (uDoppler > 0.5) {
        float vOrb = sqrt(M / r);
        vOrb = min(vOrb, 0.5);

        vec3 velDir = normalize(vec3(-p.z, 0.0, p.x));
        float vLos = dot(velDir, rayDir) * vOrb;

        float gamma = 1.0 / sqrt(max(0.01, 1.0 - vOrb * vOrb));
        float g = 1.0 / (gamma * (1.0 - vLos));
        g = clamp(g, 0.25, 4.0);

        dopplerFac = g * g * g;
        temp *= clamp(g, 0.5, 1.8);
    }

    // Gravitational redshift
    float gravFac = 1.0;
    if (uRedshift > 0.5) {
        gravFac = sqrt(max(0.1, 1.0 - RS / r));
        temp *= gravFac;
    }

    vec3 emission = blackbody(temp);
    float intensity = density * dopplerFac * gravFac * crossingBoost;

    return vec4(emission, intensity);
}

// ═══════════════════════════════════════════════════════════════════════════
// STARFIELD
// ═══════════════════════════════════════════════════════════════════════════

vec3 stars(vec3 dir, float lensing) {
    vec3 col = vec3(0.0);

    for (float i = 0.0; i < 3.0; i++) {
        float scale = 40.0 + i * 25.0;
        vec3 p = dir * scale;
        vec3 id = floor(p);
        vec3 f = fract(p) - 0.5;

        float rnd = hash3(id + i * 100.0);
        if (rnd > 0.96) {
            float d = length(f);
            float brightness = exp(-d * d * 45.0) * (1.0 - i * 0.2);
            brightness *= lensing;

            float temp = hash3(id + vec3(50.0));
            vec3 starCol = temp < 0.3 ? vec3(1.0, 0.75, 0.5) :
                           temp < 0.7 ? vec3(1.0, 0.95, 0.85) :
                                        vec3(0.8, 0.9, 1.0);
            col += starCol * brightness;
        }
    }
    return col * 0.25;
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

    // Total angular deflection (for photon ring intensity)
    float totalDeflection = 0.0;
    vec3 lastVel = vel;

    // Main integration loop
    for (int i = 0; i < MAX_STEPS; i++) {
        float r = length(pos);
        minR = min(minR, r);
        minPhotonDist = min(minPhotonDist, abs(r - PHOTON_SPHERE));

        // Event horizon
        if (r < RS * 0.52) {
            transmission = 0.0;
            break;
        }

        // Gravitational acceleration
        vec3 accel = blackHoleAccel(pos);

        // Adaptive step size - smaller near photon sphere for accuracy
        float h = STEP_SIZE;
        if (r < PHOTON_SPHERE + 1.0) {
            h *= 0.25;  // Very fine steps near photon sphere
        } else if (r < 6.0) {
            h *= 0.5;
        } else if (r > 40.0) {
            h *= 2.0;
        }

        // Leapfrog integration
        vec3 velHalf = vel + accel * h * 0.5;
        vec3 newPos = pos + velHalf * h;
        vec3 newAccel = blackHoleAccel(newPos);
        vec3 newVel = velHalf + newAccel * h * 0.5;
        newVel = normalize(newVel);

        // Track deflection
        totalDeflection += acos(clamp(dot(vel, newVel), -1.0, 1.0));

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
        lastVel = vel;
        pos = newPos;
        vel = newVel;

        // Escaped
        if (r > 80.0) break;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHOTON RING - The bright thin ring at the shadow edge
    // ═══════════════════════════════════════════════════════════════════════

    // Primary photon ring (n=1 orbit)
    float ring1Dist = abs(minR - PHOTON_SPHERE);
    float ring1 = exp(-ring1Dist * ring1Dist * 8.0) * 0.5;

    // Secondary photon ring (n=2, slightly inside)
    float ring2Dist = abs(minR - PHOTON_SPHERE * 0.95);
    float ring2 = exp(-ring2Dist * ring2Dist * 20.0) * 0.3;

    // Tertiary (n=3, even tighter)
    float ring3Dist = abs(minR - PHOTON_SPHERE * 0.92);
    float ring3 = exp(-ring3Dist * ring3Dist * 40.0) * 0.2;

    // Combined photon ring with warm color
    vec3 ringColor = vec3(1.0, 0.85, 0.6);
    col += ringColor * (ring1 + ring2 + ring3) * transmission;

    // Extra glow for highly deflected rays (rays that almost orbited)
    if (totalDeflection > PI * 0.5) {
        float orbitGlow = smoothstep(PI * 0.5, PI * 1.5, totalDeflection) * 0.3;
        col += ringColor * orbitGlow * transmission;
    }

    // Subtle shadow edge glow
    float shadowR = RS * 0.52;
    float edgeDist = minR - shadowR;
    float edgeGlow = exp(-edgeDist * edgeDist * 1.0) * 0.1;
    col += vec3(0.3, 0.15, 0.05) * edgeGlow * transmission;

    // Background stars
    if (transmission > 0.01) {
        float lensAmp = 1.0 + 3.0 * exp(-minPhotonDist * minPhotonDist);
        col += stars(vel, lensAmp) * transmission;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POST-PROCESSING
    // ═══════════════════════════════════════════════════════════════════════

    // Bloom
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col += col * smoothstep(0.4, 1.2, lum) * 0.4;

    // Tone mapping (ACES)
    col *= 0.55;
    float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    col = clamp((col * (a * col + b)) / (col * (c * col + d) + e), 0.0, 1.0);

    // Gamma
    col = pow(col, vec3(1.0 / 2.2));

    // Warm tint
    col.r *= 1.03;
    col.b *= 0.94;

    // Vignette
    float vig = 1.0 - 0.35 * pow(length(uv * 0.85), 2.0);
    col *= vig;

    // Film grain
    col += (hash2(uv * 500.0 + fract(uTime)) - 0.5) * 0.018;

    gl_FragColor = vec4(col, 1.0);
}
