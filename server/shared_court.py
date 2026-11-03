"""Server-owned two-person hearing transitions and deadlines."""
import base64
import secrets
import time
from google.cloud import firestore
from demo_security import AccessError
from court_protocol import call_hearing

# phase -> role, case field, entry index
TURNS = {0:(0,'requestedRemedy',None),1:(0,'statements',0),2:(1,'statements',1),
         3:(0,'crossQuestions',0),4:(1,'crossAnswers',1),5:(1,'crossQuestions',1),
         6:(0,'crossAnswers',0),7:(0,'rebuttals',0),8:(1,'rebuttals',1),
         10:(0,'judgeAnswers',0),11:(1,'judgeAnswers',1),14:(1,'appealReason',None),15:(0,'appealResponse',None)}
AI_PHASES={9:'questions',12:'verdict',16:'appeal'}


def ref_for(data, uid, case_id):
    if not isinstance(case_id,str) or len(case_id)>80 or not all(c.isalnum() or c in '_-' for c in case_id):
        raise AccessError(400,'Invalid case.')
    cid, couple=data.member(uid)
    root=data.db.collection('closer_couples').document(cid)
    message=root.collection('messages').document(case_id).get().to_dict()
    if not message or message.get('kind')!='court':
        raise AccessError(404,'Court summons unavailable.')
    return root, root.collection('hearings').document(case_id), couple, message


def initial(couple, message):
    claimant=message['senderId']
    respondent=next(uid for uid in couple['members'] if uid!=claimant)
    people=[claimant,respondent]
    return {'people':people,'names':[couple['names'][p] for p in people],'topic':message['text'],
            'therapyLanguage':message.get('therapyLanguage', 'en'),
            'phase':0,'joined':[],'deadline':None,'requestedRemedy':'',
            'statements':['',''],'crossQuestions':['',''],'crossAnswers':['',''],'rebuttals':['',''],
            'judgeQuestions':['',''],'judgeAnswers':['',''],'evidence':[],
            'appealReason':'','appealResponse':'','ruling':None,'firstRuling':None,'model':None,'approved':[],
            'version':0,'lease':None,'closedStatus':None,'portraits':[None,None],'scenePhotoId':None,
            'aiConsent':[],'openingResponseDone':False,'openingTriggerBy':None,'facilitatorPending':False,
            'facilitatorResponses':[],'lastTurnBy':None,'lastTurnPhase':None,'lastTurnText':'',
            'lastTurnVersion':0,'facilitatorHandledVersion':0}


def update(data, uid, case_id, body=None):
    root, ref, couple, message=ref_for(data,uid,case_id)
    if body is None:
        return ref.get().to_dict() or initial(couple,message)
    op=body.get('operation')
    @firestore.transactional
    def transition(tx):
        state=ref.get(transaction=tx).to_dict() or initial(couple,message)
        if state['phase']==18:
            raise AccessError(409,'This hearing is closed.')
        now=time.time()
        if op != 'end' and state.get('lease') and state['lease']['until']>now:
            raise AccessError(409,'The judge is reviewing. Please wait.')
        if op=='portrait':
            if state['phase']!=0 or len(state['joined'])==2:raise AccessError(409,'Set portraits before starting the hearing.')
            photo_id=body.get('photoId','')
            if not isinstance(photo_id,str) or len(photo_id)!=32 or body.get('consent') is not True:raise AccessError(400,'Photo and consent are required.')
            photo=root.collection('photos').document(photo_id).get(transaction=tx).to_dict()
            if not photo or photo['owner']!=uid:raise AccessError(403,'Use your own portrait.')
            state['portraits'][state['people'].index(uid)]=photo_id
            state['scenePhotoId']=None
        elif op=='join':
            state['joined']=list(set(state['joined']+[uid]))
            if len(state['joined'])==2 and state['deadline'] is None:state['deadline']=now+120
        elif op=='ai_consent':
            if len(state.get('joined', [])) != 2:
                raise AccessError(409,'Both partners must join before enabling Metherapy.')
            if body.get('version')!=state['version']:
                raise AccessError(409,'The session changed. Refresh before continuing.')
            consents=list(state.get('aiConsent', []))
            if uid not in consents:
                consents.append(uid)
            state['aiConsent']=consents
            if len(set(consents))==2 and not state.get('openingResponseDone'):
                state.update(facilitatorPending=True,openingTriggerBy=uid,deadline=None)
        elif op=='end':
            if uid not in state['people']:
                raise AccessError(403,'Only a session participant can end this session.')
            state.update(phase=18,closedStatus='ended',deadline=None,
                         facilitatorPending=False,lease=None)
        else:
            if len(state['joined'])!=2 and not (op=='evidence' and state['phase']==0):
                raise AccessError(409,'Wait for both partners to enter court.')
            if body.get('version')!=state['version']:
                raise AccessError(409,'The hearing changed. Refresh before continuing.')
            phase=state['phase']
            if op=='turn':
                if phase not in TURNS:
                    raise AccessError(409,'This step is not a speaking turn.')
                role,field,index=TURNS[phase]
                expired=now>=state['deadline']
                if not expired and uid!=state['people'][role]:
                    raise AccessError(403,'It is your partner’s turn.')
                value=body.get('text','')
                if not isinstance(value,str) or len(value)>2000:
                    raise AccessError(400,'Use 2000 characters or fewer.')
                value='[No answer submitted before the turn expired.]' if expired else value.strip()
                if not value:raise AccessError(400,'Enter your answer first.')
                if index is None:state[field]=value[:1000] if field=='requestedRemedy' else value
                else:state[field][index]=value
                state['phase']+=1
                state.update(lastTurnBy=state['people'].index(uid),lastTurnPhase=phase,
                             lastTurnText=value,lastTurnVersion=state['version']+1)
                if len(set(state.get('aiConsent', [])))==2:
                    state.update(facilitatorPending=True,deadline=None)
                else:
                    state['deadline']=now+120 if state['phase'] in TURNS else None
            elif op=='evidence':
                if phase != 0 and (phase not in TURNS or phase>8 or uid!=state['people'][TURNS[phase][0]] or now>=state['deadline']):
                    raise AccessError(403,'Add exhibits during your own opening, cross-examination or rebuttal turn.')
                own=state['people'].index(uid)
                if sum(e['owner']==own for e in state['evidence'])>=2:
                    raise AccessError(400,'Up to two exhibits per person.')
                photo_id=body.get('photoId','')
                if not isinstance(photo_id,str) or len(photo_id)!=32:raise AccessError(400,'Invalid photo.')
                photo=root.collection('photos').document(photo_id).get(transaction=tx).to_dict()
                if not photo or photo['owner']!=uid:raise AccessError(403,'Use your own uploaded exhibit.')
                caption=body.get('caption')
                if not isinstance(caption,str) or not caption.strip() or len(caption)>500:raise AccessError(400,'Add a caption up to 500 characters.')
                state['evidence'].append({'id':'E'+str(len(state['evidence'])+1),'owner':own,'caption':caption.strip(),'photoId':photo_id})
            elif op in {'accept','decline','appeal'}:
                if phase not in (13,17):raise AccessError(409,'There is no ruling to respond to yet.')
                if op=='appeal':
                    if phase!=13 or uid!=state['people'][1]:raise AccessError(403,'Only the respondent may use the single appeal.')
                    state.update(phase=14,approved=[],deadline=now+120)
                elif op=='decline':state.update(phase=18,closedStatus='unresolved',deadline=None)
                else:
                    state['approved']=list(set(state['approved']+[uid]))
                    if len(state['approved'])==2:state.update(phase=18,closedStatus='accepted',deadline=None)
            else:raise AccessError(400,'Unknown hearing action.')
        state['version']+=1
        tx.set(ref,state)
        if state['phase']==18:
            tx.update(root.collection('messages').document(case_id),{'status':'closed','courtStatus':state['closedStatus'],
                'agreement':state['ruling']['proposedRemedy'] if state['ruling'] else '', 'model':state['model'],'practice':False})
        return state
    return transition(data.db.transaction())


def model_review(data, uid, case_id, body, key, spark_model, security, token, request_id):
    root, ref, couple, message = ref_for(data, uid, case_id)
    operation = body.get('operation')
    @firestore.transactional
    def lock(tx):
        state = ref.get(transaction=tx).to_dict()
        if not state:
            raise AccessError(409, 'Enter the session first.')
        art = operation == 'art'
        if art:
            if state['phase'] != 0 or len(state['joined']) == 2 or not all(state.get('portraits', [])):
                raise AccessError(409, 'Both people must add a consented portrait before entering the session.')
            action = 'art'
        elif operation in {'opening', 'facilitate'}:
            if len(set(state.get('aiConsent', []))) != 2:
                raise AccessError(403, 'Both partners must agree before sharing session context with Metherapy.')
            if len(state.get('joined', [])) != 2 or not state.get('facilitatorPending'):
                raise AccessError(409, 'Metherapy is not ready to speak yet.')
            if operation == 'opening':
                if state.get('openingResponseDone'):
                    raise AccessError(409, 'Metherapy has already welcomed you.')
                action = 'opening'
            else:
                if state.get('lastTurnVersion', 0) <= state.get('facilitatorHandledVersion', 0):
                    raise AccessError(409, 'There is no new turn for Metherapy to reflect on.')
                if state['phase'] not in TURNS and state['phase'] not in AI_PHASES:
                    raise AccessError(409, 'This session step is not ready for a reflection.')
                action = AI_PHASES.get(state['phase'], 'reflection')
        else:
            if len(set(state.get('aiConsent', []))) != 2:
                raise AccessError(403, 'Both partners must agree before sharing session context with Metherapy.')
            if state['phase'] not in AI_PHASES or len(state.get('joined', [])) != 2:
                raise AccessError(409, 'Metherapy is not ready to respond yet.')
            action = AI_PHASES[state['phase']]
        if body.get('version') != state['version']:
            raise AccessError(409, 'The session changed. Refresh first.')
        if state.get('lease') and state['lease']['until'] > time.time():
            raise AccessError(409, 'Metherapy is already preparing a response.')
        tx.update(ref, {'lease': {'id': request_id, 'until': time.time() + 180}})
        return state, action

    state, action = lock(data.db.transaction())
    reservation = None
    try:
        if action == 'art':
            from muse_image import create_scene
            reservation = security.reserve(token, 'characters', request_id, case_id + ':art:' + str(state['version']))
            photos = []
            for photo_id in state['portraits']:
                raw = data.bucket.blob(f'{root.id}/{photo_id}').download_as_bytes()
                if len(raw) > 1000000:
                    raise AccessError(400, 'Portraits must be smaller than 1 MB.')
                photos.append(base64.b64encode(raw).decode())
            answer = create_scene({'photos': photos}, key)
            photo_id = secrets.token_hex(16)
            data.bucket.blob(f'{root.id}/{photo_id}').upload_from_string(
                base64.b64decode(answer['image_base64']), content_type='image/png')
            root.collection('photos').document(photo_id).set({'owner': uid})

            @firestore.transactional
            def save_art(tx):
                latest = ref.get(transaction=tx).to_dict()
                if (latest.get('lease') or {}).get('id') != request_id:
                    raise AccessError(409, 'The scene request changed.')
                latest.update(scenePhotoId=photo_id, sceneModel=answer['model'],
                              sceneResponseId=answer.get('response_id'), lease=None,
                              version=latest['version'] + 1)
                tx.set(ref, latest)
                return latest
            return save_art(data.db.transaction())

        reservation = security.reserve(
            token, 'hearing', request_id,
            case_id + ':' + action + ':' + str(state['version']))
        fields = [
            'topic', 'requestedRemedy', 'names', 'statements', 'crossQuestions',
            'crossAnswers', 'rebuttals', 'judgeQuestions', 'judgeAnswers',
            'appealReason', 'appealResponse', 'therapyLanguage',
        ]
        case = {key: state.get(key, '') for key in fields}
        case['therapyLanguage'] = state.get('therapyLanguage', 'en')
        case['latestTurn'] = {
            'participant': state.get('lastTurnBy'),
            'phase': state.get('lastTurnPhase'),
            'text': state.get('lastTurnText', ''),
        }
        case['priorRuling'] = state.get('ruling') if action == 'appeal' else None
        case['evidence'] = []
        if action not in {'opening', 'reflection'}:
            for exhibit in state.get('evidence', []):
                raw = data.bucket.blob(f"{root.id}/{exhibit['photoId']}").download_as_bytes()
                if len(raw) > 1000000:
                    raise AccessError(400, 'Evidence must be smaller than 1 MB.')
                case['evidence'].append(
                    {key: exhibit[key] for key in ['id', 'owner', 'caption']} |
                    {'image_base64': base64.b64encode(raw).decode()})
        answer = call_hearing({'action': action, 'case': case}, key, spark_model)

        @firestore.transactional
        def finish(tx):
            latest = ref.get(transaction=tx).to_dict()
            if ((latest.get('lease') or {}).get('id') != request_id or
                    latest['version'] != state['version']):
                raise AccessError(409, 'The session changed. Refresh and retry.')
            now = time.time()
            if action in {'opening', 'reflection'}:
                responses = list(latest.get('facilitatorResponses', []))
                responses.append({
                    'id': secrets.token_hex(12),
                    'message': answer['result']['message'],
                    'sourcePhase': latest.get('lastTurnPhase'),
                    'createdAt': now,
                })
                latest.update(
                    version=state['version'] + 1,
                    lease=None,
                    model=answer['model'],
                    facilitatorResponses=responses[-12:],
                    facilitatorPending=False,
                    facilitatorHandledVersion=latest.get('lastTurnVersion', 0),
                )
                if action == 'opening':
                    latest['openingResponseDone'] = True
                latest['deadline'] = now + 120 if latest['phase'] in TURNS else None
            else:
                latest.update(
                    phase=state['phase'] + 1,
                    version=state['version'] + 1,
                    lease=None,
                    model=answer['model'],
                    approved=[],
                    facilitatorPending=False,
                    facilitatorHandledVersion=latest.get('lastTurnVersion', 0),
                )
                latest['evidenceReview'] = answer['result']['evidenceReview']
                if action == 'questions':
                    latest.update(judgeQuestions=answer['result']['questions'], deadline=now + 120)
                else:
                    latest['ruling'] = answer['result']
                    if action == 'verdict':
                        latest['firstRuling'] = answer['result']
            tx.set(ref, latest)
            return latest

        return finish(data.db.transaction())
    finally:
        @firestore.transactional
        def unlock(tx):
            current = ref.get(transaction=tx).to_dict()
            if current and current.get('lease') and current['lease']['id'] == request_id:
                tx.update(ref, {'lease': None})
        unlock(data.db.transaction())
        if reservation:
            security.finish(reservation)
