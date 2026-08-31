import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

const $=id=>document.getElementById(id),canvas=$('game'),loading=$('loading'),hint=$('hint');
const renderer=new THREE.WebGLRenderer({canvas,antialias:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio||1,1.5));renderer.outputColorSpace=THREE.SRGBColorSpace;
renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.08;
renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;
const scene=new THREE.Scene();scene.background=new THREE.Color(0x91c5e4);scene.fog=new THREE.Fog(0x91c5e4,90,180);
const camera=new THREE.PerspectiveCamera(72,1,.08,230);camera.rotation.order='YXZ';scene.add(camera);
scene.add(new THREE.HemisphereLight(0xd7efff,0x51483c,2));
const sun=new THREE.DirectionalLight(0xfff1d5,3.1);sun.position.set(-45,70,30);sun.castShadow=true;
sun.shadow.mapSize.set(1536,1536);sun.shadow.camera.left=-75;sun.shadow.camera.right=75;sun.shadow.camera.top=75;sun.shadow.camera.bottom=-75;sun.shadow.camera.near=1;sun.shadow.camera.far=160;sun.shadow.camera.updateProjectionMatrix();sun.shadow.bias=-.00015;sun.shadow.normalBias=.025;scene.add(sun,sun.target);

const tl=new THREE.TextureLoader(),aniso=Math.min(8,renderer.capabilities.getMaxAnisotropy());
function tex(path,srgb=false){const t=tl.load(path);if(srgb)t.colorSpace=THREE.SRGBColorSpace;t.wrapS=t.wrapT=THREE.RepeatWrapping;t.anisotropy=aniso;return t}
function rep(t,x,y){const c=t.clone();c.wrapS=c.wrapT=THREE.RepeatWrapping;c.repeat.set(x,y);c.needsUpdate=true;return c}
const asphalt=tex('models/T_Concrete_Asphalt_BaseColor.png',true),concrete=tex('models/T_Concrete_BaseColor.png',true),concreteN=tex('models/T_Concrete_Normal.png'),dirt=tex('models/T_Dirt_BaseColor.png',true),dirtN=tex('models/T_Dirt_Normal.png');
function mat(base,normal,w,d,tint=0xffffff){const m=new THREE.MeshStandardMaterial({map:rep(base,Math.max(1,w/6),Math.max(1,d/6)),roughness:.95,color:tint});if(normal){m.normalMap=rep(normal,Math.max(1,w/6),Math.max(1,d/6));m.normalScale.set(.32,.32)}return m}
function plane(x,z,w,d,m,y=0){const q=new THREE.Mesh(new THREE.PlaneGeometry(w,d),m);q.rotation.x=-Math.PI/2;q.position.set(x,y,z);q.receiveShadow=true;scene.add(q);return q}
plane(0,0,196,196,new THREE.MeshStandardMaterial({map:rep(dirt,36,36),normalMap:rep(dirtN,36,36),normalScale:new THREE.Vector2(.25,.25),roughness:1,color:0x879382}),-.035);
const roads=[-42,0,42],blocks=[-63,-21,21,63];
for(const x of roads)plane(x,0,11,194,mat(asphalt,null,11,194,0x666a6b),.006);
for(const z of roads)plane(0,z,194,11,mat(asphalt,null,194,11,0x666a6b),.009);
for(const x of blocks)for(const z of blocks)plane(x,z,30.4,30.4,mat(concrete,concreteN,30.4,30.4,0xc8c8c0),.026);
const white=new THREE.MeshStandardMaterial({color:0xeeeadd,roughness:.9}),yellow=new THREE.MeshStandardMaterial({color:0xd9b43b,roughness:.9});
const mark=(x,z,w,d,m)=>plane(x,z,w,d,m,.02);
for(const x of roads)for(let z=-90;z<=90;z+=8)if(!roads.some(c=>Math.abs(z-c)<7))mark(x,z,.13,3.4,yellow);
for(const z of roads)for(let x=-90;x<=90;x+=8)if(!roads.some(c=>Math.abs(x-c)<7))mark(x,z,3.4,.13,yellow);
for(const x of roads)for(const z of roads)for(let k=-4;k<=4;k++){mark(x+k*.82,z-7,.42,3,white);mark(x+k*.82,z+7,.42,3,white);mark(x-7,z+k*.82,3,.42,white);mark(x+7,z+k*.82,3,.42,white)}
const curbMat=new THREE.MeshStandardMaterial({color:0xb9b9b1,roughness:.92}),gH=new THREE.BoxGeometry(30.6,.18,.22),gV=new THREE.BoxGeometry(.22,.18,30.6);
for(const x of blocks)for(const z of blocks){for(const dz of[-15.3,15.3]){const m=new THREE.Mesh(gH,curbMat);m.position.set(x,.09,z+dz);m.castShadow=m.receiveShadow=true;scene.add(m)}for(const dx of[-15.3,15.3]){const m=new THREE.Mesh(gV,curbMat);m.position.set(x+dx,.09,z);m.castShadow=m.receiveShadow=true;scene.add(m)}}

const gltf=new GLTFLoader();const load=u=>new Promise((ok,no)=>gltf.load(u,ok,undefined,no));
function prep(g,shadow=true){const o=g.scene;o.traverse(n=>{if(!n.isMesh)return;n.castShadow=shadow;n.receiveShadow=true;const a=Array.isArray(n.material)?n.material:[n.material];for(const m of a)if(m){if(m.map)m.map.anisotropy=aniso;m.needsUpdate=true}});const b=new THREE.Box3().setFromObject(o),c=b.getCenter(new THREE.Vector3()),s=b.getSize(new THREE.Vector3());o.position.set(-c.x,-b.min.y,-c.z);const r=new THREE.Group();r.add(o);return{root:r,size:s}}
const coll=[];
function place(t,x,z,r=0,s=1,solid=true){const o=t.root.clone(true);o.position.set(x,.03,z);o.rotation.y=r;o.scale.setScalar(s);scene.add(o);if(solid){const q=Math.abs(Math.sin(r))>.7,w=(q?t.size.z:t.size.x)*s,d=(q?t.size.x:t.size.z)*s;coll.push({a:x-w/2-.45,b:x+w/2+.45,c:z-d/2-.45,d:z+d/2+.45})}return o}
async function city(){const f=['Building_Large_2.gltf','Building_Medium_2_001.gltf','Building_Small_1.gltf','Prop_Planter_Single.gltf','Prop_Bollard.gltf','Prop_ManholeCover.gltf'],a=await Promise.all(f.map(n=>load('models/'+n))),B=[prep(a[0]),prep(a[1]),prep(a[2])],p=prep(a[3]),bo=prep(a[4]),mh=prep(a[5],false);let i=0;for(const x of blocks)for(const z of blocks){const t=B[(i+(x>0?1:0))%3],r=((i*3+(z>0?1:0))%4)*Math.PI/2;place(t,x,z,r,t===B[0]?.94:1);place(p,x+(x<0?12.2:-12.2),z+(z<0?12.2:-12.2),0,.92,false);i++}for(const x of roads)for(const z of roads){place(mh,x+2,z+2,0,1,false).position.y=.018;for(const ox of[-5.7,5.7])for(const oz of[-5.7,5.7])place(bo,x+ox,z+oz,0,1.1,false)}}

let yaw=0,pitch=-.02;const pos=new THREE.Vector3(0,1.72,18),rad=.46,input={mx:0,my:0,lx:0,ly:0};
function blocked(x,z){if(Math.abs(x)>92||Math.abs(z)>92)return true;return coll.some(c=>x+rad>c.a&&x-rad<c.b&&z+rad>c.c&&z-rad<c.d)}
function stick(id,kx,ky,invert=false){const b=$(id),n=b.querySelector('.nub');let pid=null;const max=43,set=e=>{const r=b.getBoundingClientRect();let x=e.clientX-r.left-r.width/2,y=e.clientY-r.top-r.height/2,L=Math.hypot(x,y);if(L>max){x*=max/L;y*=max/L}n.style.transform=`translate(calc(-50% + ${x}px),calc(-50% + ${y}px))`;input[kx]=x/max;input[ky]=(invert?-y:y)/max};b.addEventListener('pointerdown',e=>{e.preventDefault();pid=e.pointerId;b.setPointerCapture(pid);set(e)});b.addEventListener('pointermove',e=>{if(e.pointerId===pid){e.preventDefault();set(e)}});const end=e=>{if(pid!==null&&(!e||e.pointerId===pid)){pid=null;input[kx]=input[ky]=0;n.style.transform='translate(-50%,-50%)'}};b.addEventListener('pointerup',end);b.addEventListener('pointercancel',end);b.addEventListener('lostpointercapture',end)}
stick('move','mx','my',true);stick('look','lx','ly');const keys=new Set();addEventListener('keydown',e=>keys.add(e.code));addEventListener('keyup',e=>keys.delete(e.code));addEventListener('contextmenu',e=>e.preventDefault());
function resize(){const w=Math.max(1,innerWidth),h=Math.max(1,innerHeight);renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix()}addEventListener('resize',resize);resize();
let last=performance.now();function frame(now){requestAnimationFrame(frame);const dt=Math.min(.033,Math.max(.001,(now-last)/1000));last=now;let x=input.mx,y=input.my;if(keys.has('KeyA'))x--;if(keys.has('KeyD'))x++;if(keys.has('KeyW'))y++;if(keys.has('KeyS'))y--;let L=Math.hypot(x,y);if(L>1){x/=L;y/=L}yaw-=input.lx*1.95*dt;pitch=THREE.MathUtils.clamp(pitch-input.ly*1.45*dt,-1.22,1.22);const sp=keys.has('ShiftLeft')?8:5.2,si=Math.sin(yaw),co=Math.cos(yaw),dx=(x*co-y*si)*sp*dt,dz=(-x*si-y*co)*sp*dt,nx=pos.x+dx;if(!blocked(nx,pos.z))pos.x=nx;const nz=pos.z+dz;if(!blocked(pos.x,nz))pos.z=nz;camera.position.copy(pos);camera.rotation.set(pitch,yaw,0);sun.position.set(pos.x-45,70,pos.z+30);sun.target.position.set(pos.x,0,pos.z);renderer.render(scene,camera)}requestAnimationFrame(frame);
city().then(()=>{loading.style.display='none';setTimeout(()=>hint.style.opacity='0',3500)}).catch(e=>{console.error(e);const msg=(e&&e.message)?e.message:String(e);loading.textContent='読み込みに失敗しました\n'+msg;loading.style.background='rgba(120,0,0,.72)'});
