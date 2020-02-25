const fs = require("fs");

fName = [
	"Anne",
	"Kirsten",
	"Mette",
	"Hanne",
	"Helle",
	"Anna",
	"Susanne",
	"Lene",
	"Maria",
	"Marianne",
	"Lone",
	"Camilla",
	"Pia",
	"Louise",
	"Charlotte",
	"Bente",
	"Tina",
	"Gitte",
	"Inge",
	"Karen",
	"Peter",
	"Jens",
	"Michael",
	"Lars",
	"Thomas",
	"Henrik",
	"Søren",
	"Christian",
	"Jan",
	"Martin",
	"Niels",
	"Anders",
	"Morten",
	"Jesper",
	"Mads",
	"Hans",
	"Jørgen",
	"Per",
	"Rasmus",
	"Ole",
	"Daniel",
	"Stephan",
	"Nikolaj",
	"Jacob"
];

lName = [
	"Nielsen",
	"Jensen",
	"Hansen",
	"Pedersen",
	"Andersen",
	"Christensen",
	"Larsen",
	"Sørensen",
	"Rasmussen",
	"Jørgensen",
	"Petersen",
	"Madsen",
	"Kristensen",
	"Olsen",
	"Thomsen",
	"Christiansen",
	"Poulsen",
	"Johansen",
	"Møller",
	"Mortensen",
	"Lindholm"
];

function ranName() {
	return (
		fName[Math.floor(Math.random() * fName.length)] +
		" " +
		lName[Math.floor(Math.random() * lName.length)]
	);
}

function ranDate(start, dur) {
	const year = Math.floor(start + Math.random() * dur);
	let month = "0" + Math.floor(1 + Math.random() * 12);
	month = month.slice(-2);
	let day = Math.floor(1 + Math.random() * 30);
	if (month == 2) {
		day = 1 + (day % 27);
	}
	day = "0" + day;
	day = day.slice(-2);
	return [year, month, day].join("-");
}

function ranDateAfter(date) {
	date = date.split("-");
	let year = Math.floor(parseInt(date[0]) + Math.random() * 2);
	let month = 1 + (Math.floor(parseInt(date[1]) + Math.random() * 12) % 12);
	if (month <= parseInt(date[1])) year += 1;
	let day = 1 + (Math.floor(1 + Math.random() * 30) % 30);
	if (month == 2) {
		day = 1 + (day % 27);
	}
	month = ("0" + month).slice(-2);
	day = ("0" + day).slice(-2);
	return [year, month, day].join("-");
}

function ranTime() {
	const h = "0" + Math.floor(Math.random() * 24);
	const m = "0" + Math.floor(Math.random() * 4) * 15;

	return h.slice(-2) + ":" + m.slice(-2);
}

function latestDate(arr) {
	let latest = arr.shift();
	latest = latest.split(" ")[0].split("-");
	// latest = latest[0].split("-");
	arr.forEach((cur) => {
		cur = cur.split(" ")[0].split("-");
		// cur = cur[0].split("-");
		if (cur[0] > latest[0]) latest = cur;
		else if (cur[0] < latest[0]);
		else if (cur[1] > latest[1]) latest = cur;
		else if (cur[1] < latest[1]);
		else if (cur[2] > latest[2]) latest = cur;
		else if (cur[2] < latest[2]);
	});
	return latest.join("-");
}

function clientToSql() {
	let cArr = [];
	let lArr = [];
	let iArr = [];
	clientArr.forEach((client) => {
		cArr.push(
			`('${client.name}', '${client.birth}', ${client.car}, ${client.instructor}, ${client.attempts}, '${client.status}', ${client.passDay})`
		);
		client.lessons.forEach((lesson) => {
			lArr.push(`(${client.id}, ${client.instructor}, '${lesson}', ${client.car})`);
		});
		iArr.push(
			`(${Math.floor(numIns + 1 + Math.random() * 3)}, ${client.id}, '${client.interview}')`
		);
	});
	let res = [];
	res.push(
		"insert into clients (name, birth, car, instructor, attempts, status, pass_date) values\n" +
			cArr.join(",\n") +
			";"
	);
	res.push(
		"insert into lessons (client, instructor, start, car) values\n" + lArr.join(",\n") + ";"
	);
	res.push("insert into interviews (employee, client, start) values\n" + iArr.join(",\n") + ";");
	return res.join("\n");
}

function carToSql() {
	let arr = [];
	carArr.forEach((car) => {
		arr.push(`('${car.tech_check}')`);
	});
	return "insert into cars (tech_check) values\n" + arr.join(",\n") + ";";
}

function empToSql() {
	let arr = [];
	empArr.forEach((emp) => {
		arr.push(`('${emp.name}', '${emp.title}')`);
	});
	return "insert into employees (name, title) values\n" + arr.join(",\n") + ";";
}

class client {
	constructor(id) {
		this.id = id;
		this.name = ranName();
		this.birth = ranDate(1950, 50);
		this.instructor = Math.floor(1 + Math.random() * numIns);
		this.car = Math.floor(1 + Math.random() * numCars);
		this.interview = ranDate(2017, 3);
		this.lessons = [];
		let rng = Math.floor(1 + Math.random() * 15);
		for (let i = 0; i < rng; i++) {
			this.lessons[i] = ranDateAfter(this.interview) + " " + ranTime();
		}
		if (this.lessons.length >= 10) {
			this.attempts = Math.floor(Math.random() * 5);
			rng = Math.floor(1 + Math.random() * 5);
			if (rng > 3) {
				this.status = "passed";
				this.passDay = `'${latestDate(this.lessons)}'`;
			} else if (rng > 1) {
				this.status = "ready";
				this.passDay = "NULL";
			} else {
				this.status = "not_ready";
				this.passDay = "NULL";
			}
		} else {
			this.attempts = 0;
			this.status = "not_ready";
			this.passDay = "NULL";
		}
	}
}

class emp {
	constructor(id, title) {
		this.id = id;
		this.name = ranName();
		this.title = title;
	}
}

class car {
	constructor(id) {
		this.id = id;
		this.tech_check = ranDate(2020, 1);
	}
}

const numClients = 2000;
const numTech = 4;
const numAdmins = 3;
const numIns = 20;
const numCars = numIns;
const numEmps = numAdmins + numIns + numTech;
let carArr = [];
let clientArr = [];
let empArr = [];

for (let i = 0; i < numCars; i++) {
	carArr[i] = new car(i + 1);
}

for (let i = 0; i < numEmps; i++) {
	if (i < numIns) empArr[i] = new emp(i + 1, "instructor");
	else if (i < numAdmins + numIns) empArr[i] = new emp(i + 1, "administrative_staff");
	else empArr[i] = new emp(i + 1, "auto_technicians");
}

for (let i = 0; i < numClients; i++) {
	clientArr[i] = new client(i + 1);
}

let data = [];

data.push(empToSql());
data.push(carToSql());
data.push(clientToSql());

data = data.join("\n");

fs.writeFile("test-scripts/populate_tables.pgsql", data, (err) => {
	if (err) throw err;
});
