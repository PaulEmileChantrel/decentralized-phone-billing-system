pragma solidity ^0.6.0;
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol';
//Contrat de contrat téléphonique
//
//Dans un premier temps, le client faire un dépot de garentie.
//Ensuite, il peut utiliser une fonction pour payer son contrat et une autre pour rompre son contrat.
//L'opérateur peut utiliser une fonction pour collecter le forfait et une fonction pour rompre le contrat et
//collecter le dépôt si le montant dû attaint 90% du dépôt.
contract PhoneContract {
 using SafeMath for uint;

 address payable operator;
 address payable client;

 uint256 to_depose = 100000000000000000; // Montant du dépot de garentie en Wei (0.1ETH)
 uint256 B0; // Bloc initial où le contrat commence (réinitialisé lorsque le forfait est payé)
 bool deposite_done = false; //Permet de savoir si le dépôt de garentie a été fait

 uint256 Amount_to_pay = 0; //Somme du forfait à payer
 uint256 Paid_amount = 0; // Somme du forfait déjà payé (peut être supérieure à la somme due à l'opérateur)
 uint256 forfait_per_block = 1000000000000000; //forfait per block in Wei

 bool reEtrencyMutx = false; //Pour éviter les reentrency attack
 uint256 balance = 0; //Pour éviter les reentrency attack


 event cast(uint256 to_pay, uint256 paid);

 //L'opérateur doit utiliser l'adresse du client pour créer un nouveaux contrat.
 constructor(address payable _client) public{
 operator = msg.sender;
 client = _client;
 }

 //fonction pour le client -> effectuer le dépôt de garentie (nécessaire pour activer les autres fonctions)
 function deposite() public payable{
 require(!deposite_done, "Le dépôt de garentie a déjà été effectué");
 require(client == msg.sender); //optionel -> peut être
 //désactivée pour que n'importe quelle adresse puisse payer le forfait du client
 require(to_depose == msg.value,"Le dépôt de garentie doit être EXACTEMENT de 0.1ETH ");
 deposite_done = true; //Le dépôt à été effectué
 B0 = block.number; //Màj du numéro de bloc utilisé pour calculer le montant due
 }

 //fonction pour le client -> Rompre son contrat (payer le montant due et recupere son dépôt);
 //le contrat est détruit après l'appel de cette fonction
 function EndContract() public{
 require(deposite_done,"Le dépôt de garentie n a pas été effectué");
 require(client == msg.sender, "Seul le client peut utiliser cette fonction pour terminer son contrat");
 require(!reEtrencyMutx, "ReEntrency attack detected sur la fonction EndContract");
 Amount_to_pay = Amount_to_pay.add(block.number.sub(B0).mul(forfait_per_block)); //Calcul du montant dû
 reEtrencyMutx = true; //Evite une attaque de réentré dans le contrat
 if (Amount_to_pay>Paid_amount){ //Le client doit plus que ce qu'il a payer
 balance = Amount_to_pay.sub(Paid_amount); //montant que le client devrait payer
 require(to_depose>balance,"Le forfait ne peut pas être annulé par le client si il doit plus que le dépôt.");
 client.transfer(to_depose.sub(balance)); // transfert d'ETH au client : dépôt moins le montant que le client devrait payer
 operator.transfer(Amount_to_pay); //transfert d'ETH à l'operateur : montant dû
 }
 else{//Le client ne doit pas d'argent à l'opérateur
 balance = Paid_amount.sub(Amount_to_pay); //Montant que le client doit récuperer
 client.transfer(to_depose.add(balance)); // transfert d'ETH au client : dépôt de garentie + montant qu'il doit récuperer
 operator.transfer(Amount_to_pay); //transfert d'ETH à l'operateur : montant due
 }
 selfdestruct(operator); //Destruction du contrat
 }

 //fonction pour le client -> Payer son forfait (le payment peut être supérieur au montant due)
 function payForfait() public payable{
 require(deposite_done,"Le dépôt de garentie n a pas été effectué");
 require(client == msg.sender, "Seul le client peut utiliser payer le forfait"); //optionel -> peut être
 //désactivée pour que n'importe quelle adresse puisse payer le forfait du client
 Paid_amount = Paid_amount.add(msg.value); //Le montant payer par le client est mis-à-jour.
 }

 //function pour l'opérateur -> Récuperer le payment du forfait (l'opérateur ne peut pas récuperer plus
 //que le montant due)
 function withdrawPaidForfait() public {
 require(deposite_done,"Le dépôt de garentie n'a pas été effectué");
 require(operator == msg.sender,"Seul l'opérateur peut collecter le forfait");
 Amount_to_pay = Amount_to_pay.add(block.number.sub(B0).mul(forfait_per_block)); //Montant à payer
 emit cast(Amount_to_pay,Paid_amount);
 B0 = block.number; //Màj du numéro de bloc utilisé pour calculer le montant due
 require((Paid_amount-Paid_amount%forfait_per_block)!=0,"La balance du client est nulle"); //pour éviter des calculs inutils
 if (Amount_to_pay>=Paid_amount){ //Le client doit plus que ce qu'il a payer
 balance = Paid_amount.sub(Paid_amount.mod(forfait_per_block)); //La totalité de son payment (à un bloc pret) sera débiter
 Amount_to_pay = Amount_to_pay.sub(balance); //Màj du montant due
 Paid_amount = Paid_amount.sub(balance); //Màj du montant payé
 operator.transfer(balance); //transfert des ETH à l'opérateur
 }
 else{ //Le client a payer plus qu'il ne doit à l'opérateur
 balance = Amount_to_pay; //La somme due
 Paid_amount = Paid_amount.sub(Amount_to_pay); //Màj du montant payé
 Amount_to_pay = 0; //Màj du montant du
 operator.transfer(balance); //transfert des ETH à l'opérateur
 }

 }

 //fonction pour l'opérateur -> Si le client ne paye pas le forfait, l'opérateur peut préléver dans le dépôt si
 //le montant due correspond à 90% ou plus du dépôt de garentie. Le montant due est prélevé et le reste est
 //rendue au client.
 //Le contrat est détruit après l'appel de cette fonction
 function withdrawDeposit() public {
 require(deposite_done,"Le dépôt de garentie n'a pas été effectué");
 require(operator == msg.sender,"Seul le client peut utiliser cette fonction pour terminer son contrat");
 Amount_to_pay = Amount_to_pay.add(block.number.sub(B0).mul(forfait_per_block));//Montant à payer
 emit cast(Amount_to_pay,Paid_amount);
 require(Amount_to_pay>Paid_amount,"L opérateur ne peut pas terminer le contrat, il doit de l argent au client");
 require(Amount_to_pay.sub(Paid_amount).mul(10) >= to_depose.mul(9),"L opérateur ne peut pas terminer le contrat, le montant dû doit être 90% de celui du dépôt");
 //Les 90% peuvent être modifiés : entre 0% (l'opérateur peut terminer le contrat quand il veut) et
 //100% (l'opérateur doit attendre que la somme due soit égale au dépôt de garentie).
 require(!reEtrencyMutx,"Reentrency attack detected sur la fonction withdrawDeposit");
 reEtrencyMutx = true; //Evite les attaques réentrées dans le contrat
 operator.transfer(Amount_to_pay);//transfert des ETH à l'opérateur
 client.transfer(to_depose.sub(Amount_to_pay));//transfert des ETH au client
 selfdestruct(operator); //Destruction du contrat
 }


}
