import { useMemo } from 'react'
import { Canvas } from '@react-three/fiber'
import { OrbitControls, ContactShadows } from '@react-three/drei'
import * as THREE from 'three'
import { JOINTS, BONES, BALL, boneRadius, swingPath, SWING_KEYS } from '../data/swing'

const CLAY = '#AA9A7E'
const FAIRWAY = '#B4E019'
const FAIRWAY_DEEP = '#93BD10'

function clayMat() {
  return <meshStandardMaterial color={CLAY} roughness={0.78} metalness={0.02} />
}

function Limb({ a, b, radius }: { a: THREE.Vector3; b: THREE.Vector3; radius: number }) {
  const { pos, quat, len } = useMemo(() => {
    const dir = new THREE.Vector3().subVectors(b, a)
    const len = dir.length()
    const mid = new THREE.Vector3().addVectors(a, b).multiplyScalar(0.5)
    const quat = new THREE.Quaternion().setFromUnitVectors(
      new THREE.Vector3(0, 1, 0),
      dir.clone().normalize(),
    )
    return { pos: mid, quat, len }
  }, [a, b])
  return (
    <mesh position={pos} quaternion={quat} castShadow receiveShadow>
      <capsuleGeometry args={[radius, Math.max(len - radius * 0.4, 0.02), 6, 20]} />
      {clayMat()}
    </mesh>
  )
}

function Figure() {
  const v = useMemo(() => {
    const m: Record<string, THREE.Vector3> = {}
    for (const k in JOINTS) m[k] = new THREE.Vector3(...JOINTS[k])
    return m
  }, [])
  // Joint blob radius = the thickest limb meeting it, so segments fuse smoothly.
  const jointR = useMemo(() => {
    const r: Record<string, number> = {}
    for (const [a, b] of BONES) {
      const rad = boneRadius(a, b)
      r[a] = Math.max(r[a] ?? 0, rad)
      r[b] = Math.max(r[b] ?? 0, rad)
    }
    return r
  }, [])
  const clubhead = new THREE.Vector3(0, 0.03, 0.44)
  return (
    <group>
      {BONES.map(([a, b], i) => (
        <Limb key={i} a={v[a]} b={v[b]} radius={boneRadius(a, b)} />
      ))}
      {Object.entries(v).map(([k, p]) =>
        k === 'head' ? null : (
          <mesh key={k} position={p} castShadow receiveShadow>
            <sphereGeometry args={[jointR[k] ?? 0.04, 20, 20]} />
            {clayMat()}
          </mesh>
        ),
      )}
      {/* Head as a gently elongated ellipsoid */}
      <mesh position={v.head} scale={[0.098, 0.118, 0.104]} castShadow receiveShadow>
        <sphereGeometry args={[1, 32, 32]} />
        {clayMat()}
      </mesh>
      {/* Club: shaft + head */}
      <Limb a={v.hands} b={clubhead} radius={0.008} />
      <mesh position={clubhead} rotation={[0, 0, 0.5]} castShadow>
        <boxGeometry args={[0.07, 0.03, 0.028]} />
        <meshStandardMaterial color="#2A2620" roughness={0.4} metalness={0.3} />
      </mesh>
    </group>
  )
}

function SwingPlane() {
  const { pos, quat } = useMemo(() => {
    const ball = new THREE.Vector3(...SWING_KEYS[0])
    const mid = new THREE.Vector3(...SWING_KEYS[2])
    const top = new THREE.Vector3(...SWING_KEYS[3])
    const normal = new THREE.Vector3()
      .crossVectors(new THREE.Vector3().subVectors(mid, ball), new THREE.Vector3().subVectors(top, ball))
      .normalize()
    const pos = new THREE.Vector3().addVectors(ball, top).multiplyScalar(0.5).addScaledVector(normal, 0.001)
    const quat = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 0, 1), normal)
    return { pos, quat }
  }, [])
  return (
    <mesh position={pos} quaternion={quat}>
      <circleGeometry args={[1.05, 72]} />
      <meshBasicMaterial
        color={FAIRWAY}
        transparent
        opacity={0.06}
        side={THREE.DoubleSide}
        depthWrite={false}
      />
    </mesh>
  )
}

function SwingPath() {
  const { geo, tip } = useMemo(() => {
    const pts = swingPath(96)
    const curve = new THREE.CatmullRomCurve3(pts)
    return {
      geo: new THREE.TubeGeometry(curve, 120, 0.0075, 14, false),
      tip: pts[pts.length - 1],
    }
  }, [])
  return (
    <group>
      <mesh geometry={geo}>
        <meshStandardMaterial color={FAIRWAY_DEEP} roughness={0.4} metalness={0.1} />
      </mesh>
      <mesh position={tip}>
        <sphereGeometry args={[0.024, 20, 20]} />
        <meshStandardMaterial color={FAIRWAY} emissive={FAIRWAY} emissiveIntensity={0.3} roughness={0.3} />
      </mesh>
    </group>
  )
}

function Scene() {
  return (
    <group position={[0, -0.78, 0]}>
      <SwingPlane />
      <SwingPath />
      <Figure />
      <mesh position={BALL} castShadow>
        <sphereGeometry args={[0.031, 24, 24]} />
        <meshStandardMaterial color="#ffffff" roughness={0.4} />
      </mesh>
      <ContactShadows
        position={[0, 0.001, 0]}
        opacity={0.3}
        scale={3.4}
        blur={2.8}
        far={2}
        resolution={1024}
        color="#191712"
      />
    </group>
  )
}

export default function SwingScene() {
  return (
    <Canvas
      shadows
      dpr={[1, 2]}
      camera={{ position: [1.95, 0.85, 2.95], fov: 34 }}
      gl={{ antialias: true, preserveDrawingBuffer: true }}
      style={{ background: 'transparent' }}
    >
      <ambientLight intensity={0.7} />
      <directionalLight
        position={[2.5, 5.5, 3]}
        intensity={1.7}
        castShadow
        shadow-mapSize={[2048, 2048]}
        shadow-bias={-0.0002}
      />
      <directionalLight position={[-4, 2.5, -1.5]} intensity={0.5} color="#fff6e8" />
      <Scene />
      <OrbitControls
        enablePan={false}
        enableDamping
        dampingFactor={0.08}
        minDistance={2.2}
        maxDistance={5}
        minPolarAngle={0.55}
        maxPolarAngle={1.7}
        target={[0, 0.12, 0]}
      />
    </Canvas>
  )
}
