# Accretion Disk Texture Enhancement Plan

## Goal
Achieve Interstellar movie-quality accretion disk texture with dense, dynamic filamentary structure while maintaining 30+ FPS performance.

## Current State
- 6 filament layers using sine-based patterns
- Basic turbulence (2-octave FBM noise)
- Spiral shock waves
- Hot spots and ISCO chaos
- Running at ~47 FPS (17 FPS headroom)

## Reference: What Makes Interstellar's Disk Look Real

1. **Dense Filamentary Structure**
   - Thousands of thin, wispy threads
   - Multiple scales: large spirals → medium threads → fine grain
   - Wound tightly by differential rotation (Keplerian shear)

2. **Turbulent, Chaotic Appearance**
   - Not uniform - clumpy, with voids and dense regions
   - Eddies and vortices at various scales
   - Magnetic field-aligned structures

3. **Dynamic Motion**
   - Everything rotates (inner faster than outer)
   - Filaments stretch and wind over time
   - Infall motion toward center
   - Flickering and variability

4. **Color & Brightness Variation**
   - Temperature gradient (hot inner → cooler outer)
   - Doppler asymmetry (approaching side brighter/bluer)
   - Bright filament edges, darker gaps

---

## Implementation Plan

### Phase 1: Ultra-Dense Filament System
**Goal**: 10x more filaments, much finer detail

**Approach**: Layered sine patterns at exponentially increasing frequencies

```glsl
// Frequency layers: 50, 100, 200, 400, 800
// Each layer thinner (higher pow exponent)
// Varying spiral winding rates
```

**Optimizations**:
- Use `fract()` and simple math instead of `sin()` where possible
- Precompute shared values (spiralWind, shearAngle)
- Combine similar calculations

**Expected Cost**: ~2-3 FPS

---

### Phase 2: Multi-Scale Turbulence Modulation
**Goal**: Break up uniform patterns, add chaos

**Approach**: Use turbulence to modulate filament visibility

```glsl
// Turbulence creates "windows" where filaments show through
// Different turbulence scales affect different filament layers
// Creates clumpy, non-uniform appearance
```

**Techniques**:
- Modulate filament amplitude by noise
- Create density voids using noise threshold
- Add turbulent displacement to filament phase

**Expected Cost**: ~1-2 FPS (reuse existing noise)

---

### Phase 3: Fine Grain Texture Layer
**Goal**: Microscopic detail that adds "texture feel"

**Approach**: Hash-based pseudo-random grain

```glsl
// Very cheap hash function for fine grain
// Position-based (moves with disk)
// Subtle - adds roughness without dominating
```

**Techniques**:
- Fast integer hash (no sin/cos)
- Animated grain that follows rotation
- Varies with radius (finer near center)

**Expected Cost**: ~1 FPS

---

### Phase 4: Enhanced Spiral Structure
**Goal**: More prominent, wound spiral arms

**Approach**: Multiple spiral arm layers

```glsl
// Primary 2-arm spiral (existing)
// Secondary 3-arm spiral
// Tertiary fine spiral ripples
// All with sharp leading edges (shock fronts)
```

**Expected Cost**: ~1 FPS

---

### Phase 5: Filament Color Variation
**Goal**: Filaments have individual temperature/color

**Approach**: Modulate temperature per-filament

```glsl
// Bright filament cores (hotter)
// Cooler gaps between filaments
// Color shifts along filament length
```

**Expected Cost**: Minimal (reuse existing color function)

---

### Phase 6: Magnetic Field Aligned Structures
**Goal**: Anisotropic texture following field lines

**Approach**: Radial vs azimuthal structure variation

```glsl
// Near ISCO: more radial (plunging)
// Mid-disk: more azimuthal (orbiting)
// Outer: mix of both
```

**Expected Cost**: ~0.5 FPS

---

## Performance Budget

| Component | Current FPS Cost | After Optimization |
|-----------|-----------------|-------------------|
| Ray marching | ~15 FPS | ~15 FPS |
| Disk sampling | ~8 FPS | ~10 FPS |
| Filaments | ~3 FPS | ~5 FPS |
| Noise/turbulence | ~4 FPS | ~5 FPS |
| Post-processing | ~2 FPS | ~2 FPS |
| Stars | ~1 FPS | ~1 FPS |
| **Headroom** | **~17 FPS** | **~12 FPS** |

Target: Use ~12 FPS headroom for texture enhancement, maintain 35+ FPS

---

## Implementation Order

### Step 1: Filament Frequency Cascade
Add 3 more high-frequency filament layers (100, 200, 400)
```glsl
float fil6 = sin(rotPhi * 120.0 - spiralWind * 1.2);
float fil7 = sin(rotPhi * 200.0 + spiralWind * 0.5);
float fil8 = sin(rotPhi * 350.0 - r * 15.0);
```

### Step 2: Turbulence Modulation
Multiply filaments by turbulence-derived mask
```glsl
float filamentMod = 0.5 + turbulence * 0.8;
filaments *= filamentMod;
```

### Step 3: Fine Grain Layer
Add hash-based micro-texture
```glsl
float grain = hash2(vec2(rotPhi * 500.0, r * 50.0));
grain = smoothstep(0.4, 0.6, grain) * 0.15;
```

### Step 4: Spiral Enhancement
Add 3-arm secondary spiral
```glsl
float spiral3 = sin((phi - log(r) * 2.5) * 3.0 + time * 0.2);
```

### Step 5: Color Modulation
Temperature varies with filament intensity
```glsl
temp += filaments * 0.2;  // Brighter filaments are hotter
```

---

## Quality Targets

1. **Filament Count**: Visually ~1000+ distinct threads
2. **Scale Range**: From large spirals (5-10 visible) to grain (sub-pixel)
3. **Motion**: All elements animated and rotating
4. **Variation**: No two regions look identical
5. **Performance**: Stable 35+ FPS

---

## Fallback Optimizations (if FPS drops below 30)

1. Reduce MAX_STEPS (280 → 250)
2. Increase STEP_SIZE (0.25 → 0.3)
3. Reduce filament layers (keep highest impact ones)
4. Lower noise octaves (2 → 1)
5. Simplify grain to static pattern
6. Resolution scaling (last resort)

---

## Testing Checklist

- [ ] Default view (distance 35): 35+ FPS
- [ ] Zoomed in (distance 20): 30+ FPS
- [ ] Zoomed out (distance 80): 40+ FPS
- [ ] Edge-on view: 30+ FPS
- [ ] All angles smooth rotation
- [ ] No visible banding or aliasing
- [ ] Filaments clearly visible and animated
- [ ] Lensing distorts filaments correctly
