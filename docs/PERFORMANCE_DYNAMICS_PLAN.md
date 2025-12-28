# Performance & Dynamics Enhancement Plan

## Executive Summary

**Goal**: Achieve 30+ FPS while making the accretion disk dramatically more dynamic and energetic.

**Current State**:
- ~7-15 FPS (varies with camera position)
- Disk appears smooth/simplistic with subtle turbulence
- 350 ray steps with adaptive sizing
- 3-octave FBM for disk texture

**Target State**:
- 30+ FPS consistently
- Violent, energetic disk with:
  - Turbulent eddies and vortices
  - Magnetic reconnection flares
  - Hot spots and shock heating
  - Dynamic spiral density waves
  - Plasmoid-like ejections near inner edge

---

## Part A: Performance Optimization

### A1. Early Ray Termination (Impact: HIGH ~50%+ speedup)

**Current**: Rays continue for full MAX_STEPS unless they hit the event horizon or escape at r>80.

**Optimization**:
```glsl
// Early exit for rays clearly escaping (moving away from BH)
if (r > 25.0 && dot(vel, pos) > 0.0) {
    // Ray is far out and moving away - it won't come back
    break;
}

// Early exit if opacity saturated
if (transmission < 0.005) break;  // Already at 0.01, tighten further
```

**Tasks**:
- [ ] Add radial velocity check for escaping rays at r > 25
- [ ] Reduce transmission threshold from 0.01 to 0.005
- [ ] Add step count reduction for rays that don't approach photon sphere

### A2. Adaptive Step Sizing (Impact: MEDIUM ~20-30% speedup)

**Current**: Basic 4-tier adaptive stepping (0.25x, 0.5x, 1x, 2x based on radius).

**Optimization**: More aggressive far-field stepping, tighter near-field:
```glsl
float h = STEP_SIZE;
if (r < PHOTON_SPHERE + 0.5) {
    h *= 0.15;  // Ultra-fine near photon sphere
} else if (r < 5.0) {
    h *= 0.35;
} else if (r < 12.0) {
    h *= 0.7;
} else if (r > 35.0) {
    h *= 3.0;   // Very coarse far field (was 2.0)
} else if (r > 50.0) {
    h *= 5.0;   // Extremely coarse, almost no bending
}
```

**Tasks**:
- [ ] Implement 5+ tier adaptive stepping
- [ ] Tune step multipliers to maintain visual quality
- [ ] Test visual fidelity at various camera angles

### A3. Reduce MAX_STEPS with Quality Preservation (Impact: HIGH ~30-40% speedup)

**Current**: MAX_STEPS = 350

**Optimization**: With better adaptive stepping and early termination, we can reduce:
```glsl
#define MAX_STEPS 200  // Target (down from 350)
```

**Tasks**:
- [ ] Reduce MAX_STEPS to 250, test quality
- [ ] Reduce to 200, test quality
- [ ] If needed, add "quality" uniform for user toggle

### A4. Optimized Noise Functions (Impact: MEDIUM ~15-20% speedup)

**Current**: Hash-based 3D noise with 3 FBM octaves.

**Optimization**:
```glsl
// Faster hash (fewer trig ops)
float fastHash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// 2-octave FBM for distant disk, 3 for near
float fbmAdaptive(vec3 p, float dist) {
    int octaves = dist < 8.0 ? 3 : 2;
    // ...
}
```

**Tasks**:
- [ ] Replace sin-based hash with arithmetic hash
- [ ] Reduce FBM octaves based on distance to camera
- [ ] Cache noise results where possible

### A5. Star Field Optimization (Impact: LOW-MEDIUM ~10% speedup)

**Current**: 3 nested loops with hash lookups.

**Optimization**:
```glsl
// Single-layer stars with variable brightness
vec3 starsOptimized(vec3 dir, float lensing) {
    vec3 p = dir * 50.0;
    vec3 id = floor(p);
    float rnd = hash3(id);

    if (rnd > 0.94) {
        vec3 f = fract(p) - 0.5;
        float d = length(f);
        // Size and brightness from single hash
        float bright = exp(-d * d * (30.0 + rnd * 20.0));
        return vec3(1.0, 0.9, 0.8) * bright * lensing * 0.3;
    }
    return vec3(0.0);
}
```

**Tasks**:
- [ ] Reduce star layers from 3 to 1-2
- [ ] Combine brightness/color calculation
- [ ] Consider removing stars in disk region (they're occluded anyway)

### A6. Post-Processing Simplification (Impact: LOW ~5-10% speedup)

**Current**: Multiple luminance calculations, multiple mix operations.

**Optimization**:
```glsl
// Single luminance calculation, reuse
float lum = dot(col, vec3(0.299, 0.587, 0.114));

// Combined bloom in single pass
col *= 1.0 + smoothstep(0.3, 0.8, lum) * 0.5;

// Skip grain for high-performance mode
#ifdef HIGH_PERF
    // No grain
#else
    col += grain * 0.015;
#endif
```

**Tasks**:
- [ ] Merge bloom passes
- [ ] Single luminance calculation
- [ ] Optional: Add performance toggle for film grain

### A7. Shader Compilation Hints (Impact: LOW ~5%)

```glsl
// Add at top of shader
#ifdef GL_FRAGMENT_PRECISION_HIGH
    precision highp float;
#else
    precision mediump float;
#endif

// Unroll critical loops
#pragma optionNV(unroll all)
```

**Tasks**:
- [ ] Add precision hints
- [ ] Test loop unrolling pragmas
- [ ] Profile with browser dev tools

---

## Part B: Dynamic Accretion Disk

The goal is to transform the disk from a smooth, serene appearance to a violent, turbulent maelstrom of matter spiraling into oblivion.

### B1. Magnetohydrodynamic Turbulence (Core Visual)

Real accretion disks exhibit MRI (Magnetorotational Instability) turbulence—chaotic, swirling motion throughout.

**Implementation**:
```glsl
// Turbulent velocity field
vec2 turbulentVelocity(vec3 p, float time) {
    float r = length(p.xz);
    float phi = atan(p.z, p.x);

    // Multiple scales of turbulent eddies
    float turb1 = fbm(vec3(r * 2.0, phi * 3.0, time * 0.5));
    float turb2 = fbm(vec3(r * 5.0, phi * 7.0, time * 1.2));

    // Radial and angular perturbations
    float vr = (turb1 - 0.5) * 0.3;
    float vphi = (turb2 - 0.5) * 0.2;

    return vec2(vr, vphi);
}
```

**Tasks**:
- [ ] Add multi-scale turbulent velocity field
- [ ] Distort disk density based on turbulent motion
- [ ] Add visible "streaks" following turbulent flow

### B2. Hot Spots & Magnetic Reconnection Flares

Magnetic field lines in the disk periodically reconnect, releasing bursts of energy. These appear as bright, short-lived flares.

**Implementation**:
```glsl
// Hot spots that orbit and flare
float hotSpots(float r, float phi, float time) {
    float intensity = 0.0;

    // Multiple hot spots at different radii
    for (int i = 0; i < 4; i++) {
        float spotR = DISK_INNER + float(i) * 2.0 + 0.5;
        float spotOmega = keplerOmega(spotR);
        float spotPhi = float(i) * 1.57 + time * spotOmega * 0.4;

        // Flare intensity varies over time (reconnection events)
        float flarePhase = sin(time * (0.3 + float(i) * 0.1) + float(i) * 2.0);
        float flarePower = smoothstep(0.5, 1.0, flarePhase);  // Only bright half the time

        // Distance to hot spot
        float dr = abs(r - spotR);
        float dphi = abs(mod(phi - spotPhi + PI, 2.0 * PI) - PI);
        float dist = sqrt(dr * dr + (dphi * r) * (dphi * r));

        intensity += flarePower * exp(-dist * dist * 3.0);
    }

    return intensity;
}
```

**Tasks**:
- [ ] Add 4-6 orbiting hot spots
- [ ] Implement flare timing with random phases
- [ ] Hot spots should brighten temperature locally
- [ ] Add subtle color shift during flares (hotter = whiter)

### B3. Spiral Shock Waves

When material falls inward faster than the sound speed, it creates spiral shock patterns—bright arms that wind into the black hole.

**Implementation**:
```glsl
// Spiral density waves / shock fronts
float spiralShocks(float r, float phi, float time) {
    float pattern = 0.0;

    // Two-armed spiral (m=2 mode, most common)
    float spiralAngle = phi - log(r / DISK_INNER) * 2.5 + time * 0.15;
    float arm1 = sin(spiralAngle * 2.0);
    arm1 = smoothstep(0.7, 1.0, arm1);  // Sharp shock fronts

    // Trailing arm is brighter (compressed)
    float arm2 = sin(spiralAngle * 2.0 + PI);
    arm2 = smoothstep(0.7, 1.0, arm2);

    // Modulate by radius (stronger in mid-disk)
    float radialMod = exp(-pow((r - DISK_INNER * 2.0) / 4.0, 2.0));

    return (arm1 + arm2 * 0.6) * radialMod;
}
```

**Tasks**:
- [ ] Implement 2-armed logarithmic spiral pattern
- [ ] Sharp shock fronts (use smoothstep, not smooth sine)
- [ ] Add temperature boost at shock locations
- [ ] Spiral should wind inward over time

### B4. Inner Edge Chaos (ISCO Instability)

Near the ISCO (innermost stable circular orbit), matter becomes unstable and plunges chaotically. This region should be the most violent.

**Implementation**:
```glsl
// ISCO chaos zone
float iscoTurbulence(float r, float phi, float time) {
    if (r > DISK_INNER * 1.5) return 0.0;

    // Instability strength increases toward ISCO
    float proximity = 1.0 - (r - DISK_INNER) / (DISK_INNER * 0.5);
    proximity = clamp(proximity, 0.0, 1.0);

    // High-frequency chaotic motion
    float chaos = fbm(vec3(phi * 8.0, r * 4.0, time * 2.0));
    chaos = pow(chaos, 0.7);  // Increase contrast

    // Radial "plunging" streaks
    float plunge = sin(phi * 12.0 + r * 5.0 - time * 3.0);
    plunge = smoothstep(0.6, 1.0, plunge);

    return (chaos * 0.5 + plunge * 0.5) * proximity;
}
```

**Tasks**:
- [ ] Add localized high-frequency turbulence near ISCO
- [ ] Radial plunging streaks (matter falling in)
- [ ] Brightness boost from compression heating
- [ ] This region should appear "torn apart"

### B5. Plasma Blobs / Plasmoid Ejections

Magnetic reconnection can eject blobs of hot plasma outward (and inward). These appear as bright spots that drift through the disk.

**Implementation**:
```glsl
// Plasmoid blobs ejected from reconnection
float plasmoids(float r, float phi, float time) {
    float intensity = 0.0;

    // 8 plasmoids with different trajectories
    for (int i = 0; i < 8; i++) {
        float seed = float(i) * 7.31;
        float birthTime = mod(time + seed * 3.0, 15.0);

        // Ejected from mid-disk, drifts inward or outward
        float startR = DISK_INNER * 1.5 + hash(seed) * 3.0;
        float driftDir = hash(seed + 1.0) > 0.5 ? 1.0 : -1.0;
        float blobR = startR + driftDir * birthTime * 0.3;

        // Orbits at local Keplerian speed
        float blobPhi = hash(seed + 2.0) * 6.28 + keplerOmega(blobR) * time * 0.3;

        // Fade in, persist, fade out
        float life = smoothstep(0.0, 1.0, birthTime) * smoothstep(15.0, 10.0, birthTime);

        // Distance check
        float dr = r - blobR;
        float dphi = mod(phi - blobPhi + PI, 2.0 * PI) - PI;
        float dist = length(vec2(dr, dphi * r));

        intensity += life * exp(-dist * dist * 8.0) * 0.4;
    }

    return intensity;
}
```

**Tasks**:
- [ ] Implement 6-10 drifting plasmoid blobs
- [ ] Random birth/death cycle
- [ ] Both inward and outward drift
- [ ] Bright cores with diffuse halos

### B6. Vertical Disk Warping

The disk isn't perfectly flat—it wobbles and warps, especially near the inner edge due to relativistic effects.

**Implementation**:
```glsl
// Disk warp function (replaces flat y=0 check)
float diskWarp(float r, float phi, float time) {
    // Precession-driven warp
    float warp1 = sin(phi - time * 0.1) * 0.3;

    // Inner edge instability
    float innerWarp = sin(phi * 3.0 + time * 0.5) * 0.2;
    innerWarp *= exp(-pow((r - DISK_INNER) / 2.0, 2.0));

    // Combined warp amplitude (stronger toward inner edge)
    float warpAmp = DISK_HEIGHT * 3.0 * (1.0 / r);

    return (warp1 + innerWarp) * warpAmp;
}
```

**Tasks**:
- [ ] Replace flat disk plane with warped surface
- [ ] Precession-like slow wobble
- [ ] Higher frequency warping near ISCO
- [ ] Update disk crossing detection for warp

### B7. Velocity Streaks (Motion Blur Effect)

To convey the violence of motion, add directional streaking that follows the orbital velocity.

**Implementation**:
```glsl
// Orbital velocity streaks (motion blur effect)
float velocityStreaks(float r, float phi, float time) {
    float omega = keplerOmega(r);

    // Streaks aligned with orbital direction
    float streak = sin((phi + time * omega * 0.4) * 30.0 + r * 5.0);
    streak = pow(max(streak, 0.0), 3.0);  // Sharp bright streaks

    // Stronger streaks in inner disk (faster motion)
    float speedFactor = sqrt(DISK_INNER / r);

    return streak * speedFactor * 0.2;
}
```

**Tasks**:
- [ ] Add tangential streak pattern
- [ ] Streaks follow local orbital velocity
- [ ] Higher density near inner edge
- [ ] Subtle—don't overwhelm the main structure

---

## Part C: Combined Implementation

### C1. Modified sampleDisk Function

The new disk sampling will combine all dynamic elements:

```glsl
vec4 sampleDisk(vec3 p, vec3 rayDir, float time, int crossingNum) {
    float r = length(p.xz);
    float phi = atan(p.z, p.x);

    if (r < DISK_INNER * 0.95 || r > DISK_OUTER * 1.05) return vec4(0.0);

    // Base density from edges
    float innerEdge = smoothstep(DISK_INNER * 0.95, DISK_INNER * 1.02, r);
    float outerEdge = smoothstep(DISK_OUTER * 1.05, DISK_OUTER * 0.9, r);
    float density = innerEdge * outerEdge;

    // === DYNAMIC ELEMENTS ===

    // 1. MHD turbulence
    float turb = mhdTurbulence(r, phi, time);
    density *= 0.6 + 0.4 * turb;

    // 2. Spiral shocks
    float shocks = spiralShocks(r, phi, time);
    density += shocks * 0.5;

    // 3. ISCO chaos
    float chaos = iscoTurbulence(r, phi, time);
    density += chaos * 0.4;

    // 4. Hot spots
    float spots = hotSpots(r, phi, time);

    // 5. Plasmoids
    float blobs = plasmoids(r, phi, time);

    // 6. Velocity streaks
    float streaks = velocityStreaks(r, phi, time);
    density += streaks;

    // === TEMPERATURE ===
    float temp = pow(DISK_INNER / r, 0.85);
    temp += chaos * 0.3;        // ISCO heating
    temp += shocks * 0.25;      // Shock heating
    temp += spots * 0.5;        // Flare heating
    temp += blobs * 0.4;        // Plasmoid temperature

    // === COLOR ===
    vec3 emission = interstellarDiskColor(temp);

    // Flares and blobs add white-hot contribution
    emission = mix(emission, vec3(1.0, 0.95, 0.85), spots * 0.3);
    emission = mix(emission, vec3(1.0, 0.9, 0.7), blobs * 0.25);

    // === DOPPLER & REDSHIFT (existing) ===
    // ... (keep current implementation)

    float intensity = density * dopplerFac * gravFac * crossingBoost;
    return vec4(emission, intensity);
}
```

### C2. Performance-Aware Quality Settings

```glsl
// Quality presets (could be uniform-controlled)
#define QUALITY_HIGH 0
#define QUALITY_MEDIUM 1
#define QUALITY_LOW 2

#if QUALITY == QUALITY_HIGH
    #define MAX_STEPS 280
    #define TURBULENCE_OCTAVES 3
    #define HOTSPOT_COUNT 6
    #define PLASMOID_COUNT 8
#elif QUALITY == QUALITY_MEDIUM
    #define MAX_STEPS 200
    #define TURBULENCE_OCTAVES 2
    #define HOTSPOT_COUNT 4
    #define PLASMOID_COUNT 6
#else
    #define MAX_STEPS 150
    #define TURBULENCE_OCTAVES 2
    #define HOTSPOT_COUNT 3
    #define PLASMOID_COUNT 4
#endif
```

---

## Implementation Order

### Phase 1: Performance Foundation (Do First)
1. Early ray termination
2. Aggressive adaptive stepping
3. Reduce MAX_STEPS to 250
4. Optimize hash/noise functions
5. **Test**: Should see 20+ FPS

### Phase 2: Core Dynamics
1. MHD turbulence (replaces current fbm turbulence)
2. Spiral shock waves
3. ISCO chaos zone
4. **Test**: Should maintain 20+ FPS with new dynamics

### Phase 3: Flares & Highlights
1. Orbiting hot spots with flare timing
2. Plasmoid blobs
3. Velocity streaks (subtle)
4. **Test**: Tune flare intensity for visual impact

### Phase 4: Final Optimization
1. Further reduce MAX_STEPS if quality allows (target: 200)
2. Star field optimization
3. Post-processing simplification
4. Quality toggle implementation
5. **Test**: Target 30+ FPS achieved

### Phase 5: Polish
1. Disk warping (if FPS budget allows)
2. Fine-tune timing of all dynamic elements
3. Adjust color grading for increased activity
4. Add any final visual touches

---

## Success Criteria

### Performance
- [ ] 30+ FPS at 1080p on mid-range hardware
- [ ] 60+ FPS at 720p
- [ ] No visible stuttering during camera movement

### Visual Dynamics
- [ ] Disk shows clear turbulent structure
- [ ] Visible spiral shock arms winding inward
- [ ] Occasional bright flares (every 2-5 seconds)
- [ ] Inner edge appears chaotic and violent
- [ ] Distinct hot spots orbiting
- [ ] Overall impression: violent maelstrom, not serene disk

### Quality Preservation
- [ ] Black hole shadow remains crisp
- [ ] Einstein ring clearly visible
- [ ] Doppler asymmetry preserved
- [ ] Interstellar warm gold color palette maintained
- [ ] Photon rings at shadow edge intact

---

## Technical References

- MRI Turbulence: Balbus & Hawley (1991) - Magnetorotational instability
- Magnetic Reconnection in Disks: Ripperda et al. (2022) - Black hole flares
- Shock Heating: Blaes et al. - Spiral shocks in accretion disks
- Shadertoy Examples: iq's FBM techniques for efficient noise
- WebGL Optimization: Early ray termination patterns

---

## Notes

The key insight is that **dynamic elements add visual complexity without necessarily adding computational cost** if we're clever about it:

1. Hot spots are just a few localized Gaussian blobs—cheap
2. Spiral shocks are a single sine pattern—very cheap
3. ISCO chaos reuses existing FBM, just concentrated—neutral
4. Plasmoids are point-like—cheap

The expensive part is the ray marching loop, so optimizing **that** gives us budget for the dynamic elements.

The disk should feel **alive**—like watching a hurricane from space, not a calm spinning disc.
