Smalltalk createPackage: 'Tide-Amber-Core'!
Object subclass: #TDAction
	instanceVariableNames: 'promise resolved'
	package: 'Tide-Amber-Core'!

!TDAction methodsFor: 'accessing'!

client
	^ self promise client
!

promise
	^ promise
!

promise: aPromise
	promise := aPromise
! !

!TDAction methodsFor: 'resolving'!

beResolved
	resolved := true.
	self promise nextTravel
!

resolve
	self beResolved
! !

!TDAction methodsFor: 'testing'!

isResolved
	^ resolved ifNil: [ false ]
! !

!TDAction class methodsFor: 'instance creation'!

on: aPromise
	^ self new 
		promise: aPromise; 
		yourself
! !

TDAction subclass: #TDCallbackAction
	instanceVariableNames: 'callback'
	package: 'Tide-Amber-Core'!

!TDCallbackAction methodsFor: 'accessing'!

callback
	^ callback
!

callback: aBlock
	callback := aBlock
! !

!TDCallbackAction methodsFor: 'resolving'!

resolve
	self client promisedValue: (self callback value: self client promisedValue).
	super resolve
! !

TDAction subclass: #TDRequestAction
	instanceVariableNames: 'requestUrl data'
	package: 'Tide-Amber-Core'!

!TDRequestAction methodsFor: 'accessing'!

data
	^ data
!

data: json
	data := json
!

requestUrl
	^ requestUrl
!

requestUrl: aString
	requestUrl := aString
! !

!TDRequestAction methodsFor: 'error handling'!

requestError: anObject
	TDRequestError new
		xhr: anObject;
		signal
!

sessionNotFound
	TDSessionNotFound signal
! !

!TDRequestAction methodsFor: 'private'!

newClientFromJson: json
	self client promisedValue: json asTideObject
!

serverErrorFromJson: json
	| serverError error |

	serverError := json asTideObject.	
	error := TDServerError new 
		code: serverError code;
		messageText: serverError messageText;
		yourself.
		
	self promise errorHandler 
		ifNotNil: [ :handler | handler failure: error ]
		ifNil: [ error signal ].
!

updateClientFromJson: json
	self client updateFromJson: json
! !

!TDRequestAction methodsFor: 'resolving'!

handleResponse: json status: aNumber
	aNumber == 200 ifTrue: [ ^ self updateClientFromJson: json ].
	aNumber == 201 ifTrue: [ ^ self newClientFromJson: json ].
	aNumber == 202 ifTrue: [ ^ self serverErrorFromJson: json ].
	
	self error: 'Invalid server answer code'.
!

request: aString
	jQuery 
		ajax: self requestUrl
		options: #{
			'type' -> 'POST'.
			'dataType' -> 'json'.
			'data' -> #{ 'arguments' -> self data }.
			'success' -> [ :json :textStatus :xhr |
				self handleResponse: json status: xhr status.
				self beResolved ].
			'error' -> [ :ex |
				ex status = 408 
					ifTrue: [ self sessionNotFound ]
					ifFalse: [ self requestError: ex ] ]
		}
!

resolve
	self request: self requestUrl
! !

Object subclass: #TDAsyncPromiseFailureHandler
	instanceVariableNames: 'failureAction action'
	package: 'Tide-Amber-Core'!

!TDAsyncPromiseFailureHandler methodsFor: 'accessing'!

action 
	^ action
! !

!TDAsyncPromiseFailureHandler methodsFor: 'initialization'!

initializeAction: aBlock  
	self initialize.
	action := aBlock.
! !

!TDAsyncPromiseFailureHandler methodsFor: 'signaling'!

failure: anError
	self action value: anError
! !

!TDAsyncPromiseFailureHandler class methodsFor: 'instance creation'!

action: aBlock 
	^ self basicNew 
		initializeAction: aBlock;
		yourself
!

new 
	^ self error: 'Use #action:'
! !

Object subclass: #TDClient
	instanceVariableNames: 'state actions firstPromise promisedValue path id connected'
	package: 'Tide-Amber-Core'!

!TDClient methodsFor: 'accessing'!

actions
	^ actions
!

flushPromises
	firstPromise := nil
!

future
	| promise |

	promise := TDPromise on: self.

	firstPromise 
		ifNil: [ firstPromise := promise ]
		ifNotNil: [ firstPromise next: promise ].

	^ promise
!

id
	^ id
!

path
	^ path
!

path: aString
	path := aString
!

promisedValue
	^ promisedValue
!

promisedValue: anObject
	promisedValue := anObject
!

state
	^ state
! !

!TDClient methodsFor: 'converting'!

asTideArgument
	^ #{ '__id__' -> self id }
! !

!TDClient methodsFor: 'error handling'!

promiseNotFound: aSelector
	TDPromiseNotFound new
		selector: aSelector;
		signal
! !

!TDClient methodsFor: 'forwarding'!

handleFutureMessage: aMessage
	| selector |
	selector := aMessage selector asString.
	
	(state at: selector) 
		ifNotNil: [ ^ state at: selector ].

	(actions at: selector) 
		ifNotNil: [ ^ self future setRequestActionFromMessage: aMessage ].

	^ self promiseNotFound: aMessage selector
!

then: aBlock
	self future then: aBlock
! !

!TDClient methodsFor: 'initialization'!

connect
	self isConnected ifFalse: [ self update ]
!

initialize
	super initialize.
	"Primitive JS object. I need it because I'm keeping JSON data"
	state := self newJavaScriptObject. 
	actions := self newJavaScriptObject
! !

!TDClient methodsFor: 'private'!

newJavaScriptObject
	<return {}>
! !

!TDClient methodsFor: 'testing'!

isConnected
	^ connected ifNil: [ false ]
! !

!TDClient methodsFor: 'updating'!

update
	| promise |
	promise := self future.
	promise setAction: ((TDRequestAction on: promise)
		requestUrl: self path;
		yourself).
	self future then: [ connected := true ]
!

updateActions: aDictionary
	aDictionary keysAndValuesDo: [ :key :value |
			actions at: key put: value ]
!

updateFromJson: json
	connected := true.
	
	id := json at: '__id__'.
	
	(json at: 'state') ifNotNil: [
		json state keysAndValuesDo: [ :key :value |
			state at: key put: value asTideObject ] ].
	(json at: 'actions') ifNotNil: [
		json actions keysAndValuesDo: [ :key :value |
			actions at: key put: value ] ]
!

updateState: aDictionary
	aDictionary keysAndValuesDo: [ :key :value |
			state at: key put: value ]
! !

!TDClient class methodsFor: 'instance creation'!

fromJson: json
	^ self new
		updateFromJson: json;
		yourself
!

on: aString
	^ self new
		path: aString;
		yourself
! !

Object subclass: #TDPromise
	instanceVariableNames: 'previous next client action errorHandler'
	package: 'Tide-Amber-Core'!

!TDPromise methodsFor: 'accessing'!

action
	^ action
!

client
	^ client
!

client: aClient
	client := aClient
!

errorHandler
	^ errorHandler
!

future
	^ self client future
!

next
	^ next
!

next: aPromise
	next 
		ifNil: [ 
			next := aPromise. 
			aPromise previous: self ]
		ifNotNil: [ 
			next next: aPromise ]
!

previous
	^ previous
!

previous: aPromise
	previous := aPromise
!

setAction: anAction
	action := anAction.
	self travel
! !

!TDPromise methodsFor: 'actions'!

setRequestActionFromMessage: aMessage
	| url data |
	url := self client actions at: aMessage selector.
	data := JSON stringify: ((aMessage arguments ifNil: [ #() ]) 
		collect: [ :each | each asTideArgument ]).
	self setAction: ((TDRequestAction on: self)
		requestUrl: url;
		data: data;
		yourself)
!

then: aBlock
	self isAssigned
		ifTrue: [ self client future then: aBlock ]
		ifFalse: [ self setAction: ((TDCallbackAction on: self) callback: aBlock) ]
! !

!TDPromise methodsFor: 'initialization'!

initialize
	super initialize.
	errorHandler := self class errorHandler.
! !

!TDPromise methodsFor: 'testing'!

isAssigned
	^ self action notNil
!

isResolved
	^ self isAssigned and: [ self action isResolved ]
! !

!TDPromise methodsFor: 'traveling'!

nextTravel
	self next 
		ifNil: [ self client flushPromises ]
		ifNotNil: [ self next stepTravel ]
!

stepTravel
	self action 
		ifNil: [ self nextTravel ]
		ifNotNil: [ self action resolve ]
!

travel
	(self previous isNil or: [ self previous isResolved ]) 
		ifTrue: [ self stepTravel ]
! !

TDPromise class instanceVariableNames: 'errorHandler'!

!TDPromise class methodsFor: 'accessing'!

errorHandler 
	^ errorHandler
!

errorHandler: anErrorHandler 
	errorHandler := anErrorHandler
!

use: anErrorHandler during: aBlock
	| oldErrorHandler |
	
	oldErrorHandler := self errorHandler.
	self errorHandler: anErrorHandler.
	aBlock ensure: [ self errorHandler: oldErrorHandler ]
! !

!TDPromise class methodsFor: 'instance creation'!

on: aClient
	^ self new
		client: aClient;
		yourself
! !

ProtoObject subclass: #TDProxy
	instanceVariableNames: 'client'
	package: 'Tide-Amber-Core'!

!TDProxy methodsFor: 'accessing'!

xxxClient
	^ client
!

xxxClient: aClient
	client := aClient
! !

!TDProxy methodsFor: 'as yet unclassified'!

inspectOn: anInspector
	anInspector
		setLabel: self printString;
		setVariables: #{
			'client' -> client
		}
! !

!TDProxy methodsFor: 'converting'!

asTideArgument
	^ self xxxClient asTideArgument
! !

!TDProxy methodsFor: 'error handling'!

doesNotUnderstand: aMessage
	^ (self xxxClient respondsTo: aMessage selector)
		ifTrue: [ aMessage sendTo: self xxxClient ]
		ifFalse: [ self xxxClient handleFutureMessage: aMessage ]
! !

!TDProxy methodsFor: 'initialization'!

initialize
	super initialize.
	"self inheritedSelectors do: [ :each |
		self removeSelector: each asSelector ]"
! !

!TDProxy methodsFor: 'private'!

inheritedSelectors
	^ self class allSelectors
		reject: [ :each | TDProxy methodDictionary keys includes: each ]
!

removeSelector: aString
	<delete self[aString];>
! !

!TDProxy class methodsFor: 'instance creation'!

client: aClient
	"Do not add yourself here.
	It is not understood by the proxy after sending #initialize, therefore it returns aClient"

	^ self basicNew
		xxxClient: aClient;
		initialize
!

connectOn: aPath
	"Creates a proxy on aPath and connect it. 
	 This is a convenience method."
	 
	^ (self on: aPath) 
		connect; 
		yourself.
!

on: aPath
	"Do not add yourself here.
	It is not understood by the proxy after sending #initialize, therefore it returns aPath"

	^ self basicNew
		xxxClient: (TDClient on: aPath);
		initialize
! !

!Array methodsFor: '*Tide-Amber-Core'!

asTideObject
	^ self collect: [ :each | each asTideObject ]
! !

!BlockClosure methodsFor: '*Tide-Amber-Core'!

onPromiseFailureDo: failureBlock
	^ TDPromise
		use: (TDAsyncPromiseFailureHandler action: failureBlock)
		during: self
! !

!HashedCollection methodsFor: '*Tide-Amber-Core'!

asTideObject
	| dictionary |
	dictionary := self class new.
	self keysAndValuesDo: [ :key :value | 
		dictionary at: key put: value asTideObject ].
		
	^ dictionary
! !

!JSObjectProxy methodsFor: '*Tide-Amber-Core'!

asTideObject
	^ TDProxy client: (TDClient fromJson: self)
! !

!Object methodsFor: '*Tide-Amber-Core'!

asTideArgument
	^ self
!

asTideObject
	^ self
! !

